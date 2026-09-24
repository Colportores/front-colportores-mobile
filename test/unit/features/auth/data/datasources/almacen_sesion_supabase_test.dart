// HU-AUTH-007 — dónde guarda supabase_flutter la sesión y la puerta de los 30 días sin uso.
import 'dart:convert';

import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/almacen_sesion_supabase.dart';
import 'package:colportores_mobile/features/auth/data/datasources/emision_jwt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

import '../../../../../helpers/logger_mudo.dart';

class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

/// Lo que guardaba supabase_flutter antes (SharedPreferences), en memoria.
final class _Anterior implements LocalStorage {
  _Anterior([this.valor]);

  String? valor;
  bool inicializado = false;

  @override
  Future<void> initialize() async => inicializado = true;

  @override
  Future<bool> hasAccessToken() async => valor != null;

  @override
  Future<String?> accessToken() async => valor;

  @override
  Future<void> persistSession(String persistSessionString) async => valor = persistSessionString;

  @override
  Future<void> removePersistedSession() async => valor = null;
}

String _jwtEmitidoEn(DateTime emitido) {
  String parte(Map<String, Object?> datos) =>
      base64Url.encode(utf8.encode(jsonEncode(datos))).replaceAll('=', '');
  return '${parte({'alg': 'HS256'})}.'
      '${parte({'sub': 'u', 'iat': emitido.millisecondsSinceEpoch ~/ 1000})}.firma';
}

String _sesionEmitidaEn(DateTime emitido) =>
    jsonEncode({'access_token': _jwtEmitidoEn(emitido), 'refresh_token': 'r'});

void main() {
  final ahora = DateTime.utc(2026, 9, 23, 12);
  late AlmacenSeguroEnMemoria almacen;

  AlmacenSesionSupabase crear({LocalStorage? anterior, AppLogger? logger}) => AlmacenSesionSupabase(
    almacen,
    anterior: anterior,
    ahora: () => ahora,
    logger: logger ?? loggerMudo(),
  );

  setUp(() => almacen = AlmacenSeguroEnMemoria());

  group('guarda la sesión en el almacén seguro', () {
    test('Escenario: Refresh transparente con uso regular — cada sesión nueva reemplaza la '
        'anterior en el almacén seguro', () async {
      final sesiones = crear();

      await sesiones.persistSession(_sesionEmitidaEn(ahora.subtract(const Duration(days: 5))));
      await sesiones.persistSession(_sesionEmitidaEn(ahora));

      expect(almacen.contenido[ClaveSegura.sesionAuth], _sesionEmitidaEn(ahora));
      expect(await sesiones.accessToken(), _sesionEmitidaEn(ahora));
      expect(await sesiones.hasAccessToken(), isTrue);
    });

    test('removePersistedSession la borra', () async {
      final sesiones = crear();
      await sesiones.persistSession(_sesionEmitidaEn(ahora));

      await sesiones.removePersistedSession();

      expect(almacen.contenido, isEmpty);
      expect(await sesiones.hasAccessToken(), isFalse);
    });

    test('una falla del almacén no rompe al proveedor: queda en el log', () async {
      final salida = _SalidaEnMemoria();
      final sesiones = crear(logger: AppLogger(output: salida));
      almacen.simularFalla = true;

      await sesiones.persistSession(_sesionEmitidaEn(ahora));
      await sesiones.removePersistedSession();

      expect(salida.lineas.join('\n'), contains('SESION_GUARDAR_FAIL'));
      expect(salida.lineas.join('\n'), contains('SESION_BORRAR_FAIL'));
    });

    test('si no se puede leer, arranca sin sesión pero no borra nada', () async {
      almacen = AlmacenSeguroEnMemoria({ClaveSegura.sesionAuth: _sesionEmitidaEn(ahora)});
      final sesiones = crear();
      almacen.simularFalla = true;

      expect(await sesiones.accessToken(), isNull);

      almacen.simularFalla = false;
      expect(almacen.contenido[ClaveSegura.sesionAuth], isNotNull);
      expect(sesiones.tomarVencimiento(), isFalse);
    });
  });

  group('la puerta de los 30 días (HU-AUTH-007)', () {
    test('dentro de la ventana (25 días sin uso) entrega la sesión', () async {
      almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.sesionAuth: _sesionEmitidaEn(ahora.subtract(const Duration(days: 25))),
      });

      expect(await crear().accessToken(), isNotNull);
    });

    test('pasados los 30 días por menos de 5 min (reloj desfasado), la entrega igual', () async {
      almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.sesionAuth: _sesionEmitidaEn(
          ahora.subtract(const Duration(days: 30, minutes: 4)),
        ),
      });

      expect(await crear().accessToken(), isNotNull);
    });

    test('Escenario: Expiración por inactividad — pasados los 30 días no la entrega: la borra, '
        'lo avisa una vez y no toca nada más del almacén', () async {
      almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.sesionAuth: _sesionEmitidaEn(ahora.subtract(const Duration(days: 31))),
        ClaveSegura.salDb: 'sal',
      });
      final sesiones = crear();
      final avisos = <void>[];
      final suscripcion = sesiones.vencimientos.listen(avisos.add);
      addTearDown(suscripcion.cancel);

      expect(await sesiones.hasAccessToken(), isFalse);
      expect(await sesiones.accessToken(), isNull);
      await Future<void>.delayed(Duration.zero);

      expect(almacen.contenido, {ClaveSegura.salDb: 'sal'});
      expect(avisos, hasLength(1));
      expect(sesiones.tomarVencimiento(), isTrue);
      expect(sesiones.tomarVencimiento(), isFalse);
    });

    for (final (caso, guardada) in [
      ('un JSON roto', '{"access_token": "eyJ'),
      (
        'un JWT sin iat',
        jsonEncode({'access_token': 'a.${base64Url.encode(utf8.encode('{}'))}.c'}),
      ),
      ('un JWT que no es JWT', jsonEncode({'access_token': 'no-es-un-jwt'})),
      ('algo sin access_token', jsonEncode({'otra': 1})),
    ]) {
      test('dado $caso, la descarta sin dejar el contenido en el log', () async {
        almacen = AlmacenSeguroEnMemoria({ClaveSegura.sesionAuth: guardada});
        final salida = _SalidaEnMemoria();

        expect(await crear(logger: AppLogger(output: salida)).accessToken(), isNull);

        expect(almacen.contenido, isEmpty);
        expect(salida.lineas.join('\n'), contains('SESION_ILEGIBLE'));
        expect(salida.lineas.join('\n'), isNot(contains('access_token')));
        expect(salida.lineas.join('\n'), isNot(contains('eyJ')));
      });
    }
  });

  group('migración desde SharedPreferences', () {
    test('mueve la sesión al almacén seguro y la borra de SharedPreferences', () async {
      final anterior = _Anterior(_sesionEmitidaEn(ahora));

      await crear(anterior: anterior).initialize();

      expect(anterior.inicializado, isTrue);
      expect(anterior.valor, isNull);
      expect(almacen.contenido[ClaveSegura.sesionAuth], _sesionEmitidaEn(ahora));
    });

    test('si el almacén seguro ya tiene una, se queda con esa y limpia la vieja', () async {
      almacen = AlmacenSeguroEnMemoria({ClaveSegura.sesionAuth: 'la-nueva'});
      final anterior = _Anterior(_sesionEmitidaEn(ahora));

      await crear(anterior: anterior).initialize();

      expect(almacen.contenido[ClaveSegura.sesionAuth], 'la-nueva');
      expect(anterior.valor, isNull);
    });

    test('si no puede escribir en el almacén seguro, no borra la vieja (reintenta al próximo '
        'arranque)', () async {
      final anterior = _Anterior(_sesionEmitidaEn(ahora));
      almacen.simularFalla = true;

      await crear(anterior: anterior).initialize();

      expect(anterior.valor, isNotNull);
    });

    test('sin sesión vieja o sin almacén anterior, no hace nada', () async {
      final anterior = _Anterior();

      await crear(anterior: anterior).initialize();
      await crear().initialize();

      expect(almacen.contenido, isEmpty);
    });
  });

  test('emisionDelJwt lee el iat con el reloj del servidor (UTC)', () {
    final emitido = DateTime.utc(2026, 9, 1, 8, 30);

    expect(emisionDelJwt(_jwtEmitidoEn(emitido)), emitido);
    expect(emisionDelJwt('a.%%%.c'), isNull);
  });
}

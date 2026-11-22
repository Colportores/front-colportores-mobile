// HU-AUTH-008 — el estado de la cuenta sale de la RPC `estado_cuenta()` de Supabase. Importa
// supabase_flutter (que arrastra Flutter), así que usa flutter_test y no `test`.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_remote_data_source_supabase.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../helpers/logger_mudo.dart';

EstadoCuentaSupabase _fuente(Future<Object?> Function() rpc) =>
    EstadoCuentaSupabase(rpc, logger: loggerMudo());

Matcher _servidorConStatus(int? status) =>
    isA<ServidorException>().having((e) => e.status, 'status', status);

void main() {
  group('dado que el servidor contesta', () {
    test('cuando la cuenta está ACTIVA, entonces es activa', () async {
      expect(await _fuente(() async => 'ACTIVA').consultar(), EstadoCuenta.activa);
    });

    test('cuando está PENDIENTE_ASIGNACION, entonces es pendienteAsignacion', () async {
      expect(
        await _fuente(() async => 'PENDIENTE_ASIGNACION').consultar(),
        EstadoCuenta.pendienteAsignacion,
      );
    });

    test('cuando está SUSPENDIDA, entonces es suspendida', () async {
      expect(await _fuente(() async => 'SUSPENDIDA').consultar(), EstadoCuenta.suspendida);
    });

    for (final raro in <Object?>[
      null,
      '',
      'activa',
      'SOFT_DELETED',
      7,
      <String>['ACTIVA'],
    ]) {
      test('cuando contesta un valor que la app no conoce ($raro), no afirma nada', () async {
        // Ni activa ni pendiente: la pantalla muestra «No pudimos consultar…» y deja reintentar.
        await expectLater(_fuente(() async => raro).consultar(), throwsA(_servidorConStatus(200)));
      });
    }
  });

  group('dado que la llamada falla', () {
    test('cuando no hay sesión válida (42501), entonces es un error del servidor 401', () async {
      final fuente = _fuente(
        () async => throw const PostgrestException(message: 'permission denied', code: '42501'),
      );
      await expectLater(fuente.consultar(), throwsA(_servidorConStatus(401)));
    });

    test('cuando no existe el perfil (P0002), entonces es un error del servidor 404', () async {
      final fuente = _fuente(
        () async => throw const PostgrestException(message: 'no encontrado', code: 'P0002'),
      );
      await expectLater(fuente.consultar(), throwsA(_servidorConStatus(404)));
    });

    test('cuando el servidor responde con un código HTTP, entonces lo lleva como status', () async {
      final fuente = _fuente(
        () async => throw const PostgrestException(message: 'upstream', code: '503'),
      );
      await expectLater(fuente.consultar(), throwsA(_servidorConStatus(503)));
    });

    test('cuando el error no trae código, entonces es un error del servidor sin status', () async {
      final fuente = _fuente(() async => throw const PostgrestException(message: 'raro'));
      await expectLater(fuente.consultar(), throwsA(_servidorConStatus(null)));
    });

    test(
      'cuando el error lleva datos del usuario en el mensaje, no llegan a la excepción',
      () async {
        final fuente = _fuente(
          () async => throw const PostgrestException(message: 'lucia@ejemplo.uy', code: '500'),
        );
        await expectLater(
          fuente.consultar(),
          throwsA(isA<ServidorException>().having((e) => e.mensaje, 'mensaje', isNull)),
        );
      },
    );

    final fallasDeRed = <String, Object>{
      'sin red (SocketException)': const SocketException('sin ruta'),
      'corte a mitad (ClientException)': http.ClientException('cortado'),
      'tiempo agotado (TimeoutException)': TimeoutException('lento'),
      'la sesión no se pudo renovar por la red': AuthRetryableFetchException(message: 'sin red'),
    };
    fallasDeRed.forEach((nombre, falla) {
      test('cuando hay $nombre, entonces es sin conexión', () async {
        final fuente = _fuente(() async => throw falla);
        await expectLater(fuente.consultar(), throwsA(isA<SinConexionException>()));
      });
    });

    test('cuando la sesión no se pudo renovar por otra causa, entonces es un error 401', () async {
      final fuente = _fuente(() async => throw const AuthException('vencida', code: 'bad_jwt'));
      await expectLater(fuente.consultar(), throwsA(_servidorConStatus(401)));
    });

    test('cuando falla algo que no es de red ni del servidor, sube tal cual', () async {
      final fuente = _fuente(() async => throw StateError('boom'));
      await expectLater(fuente.consultar(), throwsA(isA<StateError>()));
    });
  });

  test(
    'dos consultas seguidas llaman a la RPC dos veces (no se guarda nada entre ellas)',
    () async {
      var llamadas = 0;
      final fuente = _fuente(() async => ++llamadas == 1 ? 'PENDIENTE_ASIGNACION' : 'ACTIVA');

      expect(await fuente.consultar(), EstadoCuenta.pendienteAsignacion);
      expect(await fuente.consultar(), EstadoCuenta.activa);
      expect(llamadas, 2);
    },
  );
}

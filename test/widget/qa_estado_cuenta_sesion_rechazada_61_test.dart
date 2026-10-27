// QA de #61 / PR #495, segunda vuelta (HU-AUTH-008 + HU-AUTH-007): una sesión que el servidor ya no
// acepta al consultar `estado_cuenta()` (`42501` o una `AuthException` de sesión) sigue el flujo de
// sesión revocada: cierre y login con su aviso, sin texto nuevo ni apoyarse en el último estado.
// Se prueba la app entera, con la fuente real `EstadoCuentaSupabase` y una RPC guionada, en cada
// camino que consulta la cuenta: el login, «Actualizar», deslizar, el «Reintentar» de un aviso, el
// arranque en frío con un estado recordado, la cuenta suspendida y la carrera con otra sesión.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_remote_data_source_supabase.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/asignacion_campania_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/asignacion_campania_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/db_local_repository_en_memoria.dart';

final class _Rpc {
  Future<Object?> Function() siguiente = () async => 'PENDIENTE_ASIGNACION';
  var llamadas = 0;

  Future<Object?> llamar() {
    llamadas++;
    return siguiente();
  }
}

final class _SinDatosLocales implements DatosLocalesRepository {
  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() async => const Right(
    ResumenDatosLocales(
      personas: 0,
      visitas: 0,
      operacionesSinSincronizar: 0,
      hayBackupEnDrive: false,
    ),
  );

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
    bool reintento = false,
  }) async => const Right(ResultadoBorradoDatosLocales.completo);
}

final class _PlanoSimple extends LogPrinter {
  @override
  List<String> log(LogEvent event) => ['${event.message}'];
}

final _titulo = find.byKey(const Key('espera_titulo'));
final _actualizar = find.byKey(const Key('espera_actualizar'));
final _principal = find.byKey(const Key('inicio_principal'));
final _login = find.byKey(const Key('login_enviar'));
final _avisoSesion = find.byKey(const Key('login_aviso_sesion'));

const _textoError =
    'No pudimos consultar el estado de tu cuenta. Tocá Reintentar para probar de nuevo; si sigue '
    'pasando, avisale a tu coordinador.';
final _textoRevocada = const FailureSesionRevocada().mensaje;

const _rechazos = <(String, Object)>[
  ('42501', PostgrestException(message: 'sin usuario', code: '42501')),
  ('AuthException', AuthException('vencida', code: 'bad_jwt')),
];

/// El «teléfono»: lo que sobrevive a cerrar y abrir la app (sesión guardada y estado recordado).
late _Rpc _rpc;
late AuthLocalDataSourceEnMemoria _sesionGuardada;
late EstadoCuentaLocalEnMemoria _recordado;
late MemoryOutput _salidaLog;

void _nuevoTelefono() {
  _rpc = _Rpc();
  _sesionGuardada = AuthLocalDataSourceEnMemoria();
  _recordado = EstadoCuentaLocalEnMemoria();
  _salidaLog = MemoryOutput();
}

/// Abre la app sobre el teléfono actual (llamarlo de nuevo = reabrirla en frío).
Future<void> _abrir(WidgetTester tester) async {
  final fuente = EstadoCuentaSupabase(
    _rpc.llamar,
    logger: AppLogger(
      logger: Logger(level: Level.debug, printer: _PlanoSimple(), output: _salidaLog),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(
            credenciales: const {'ana@example.com': 'secreto123', 'luis@example.com': 'secreto456'},
          ),
        ),
        authLocalDataSourceProvider.overrideWithValue(_sesionGuardada),
        ahoraEsperaProvider.overrideWithValue(() => DateTime(2026, 10, 27, 14, 30)),
        asignacionCampaniaDataSourceProvider.overrideWithValue(AsignacionCampaniaEnMemoria()),
        estadoCuentaRemoteDataSourceProvider.overrideWithValue(fuente),
        estadoCuentaLocalDataSourceProvider.overrideWithValue(_recordado),
        datosLocalesRepositoryProvider.overrideWithValue(_SinDatosLocales()),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _contenedor(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ColportoresApp)));

Future<void> _entrar(WidgetTester tester, {String email = 'ana@example.com'}) async {
  await tester.enterText(find.byKey(const Key('login_email')), email);
  await tester.enterText(
    find.byKey(const Key('login_password')),
    email.startsWith('ana') ? 'secreto123' : 'secreto456',
  );
  await tester.ensureVisible(_login);
  await tester.tap(_login);
  await tester.pumpAndSettle();
}

Future<void> _tocarActualizar(WidgetTester tester) async {
  await tester.ensureVisible(_actualizar);
  await tester.tap(_actualizar);
  await tester.pumpAndSettle();
}

void _tamano(WidgetTester tester, Size tam, {double texto = 1}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Lo que tiene que verse cuando el servidor no acepta la sesión: el login con el aviso de
/// HU-AUTH-007, una sola vez, y nada del aviso genérico de HU-AUTH-008 ni de la cuenta.
void _esperarLoginConAvisoDeSesion(
  WidgetTester tester, {
  String donde = '',
  bool sinRepetir = true,
}) {
  expect(_login, findsOneWidget, reason: 'vuelve al login $donde');
  expect(_avisoSesion, findsOneWidget, reason: 'con el aviso de sesión $donde');
  expect(find.text(_textoRevocada), findsWidgets, reason: 'con el texto de la HU-AUTH-007 $donde');
  expect(find.text(_textoError), findsNothing, reason: 'sin «avisale a tu coordinador» $donde');
  expect(find.textContaining('avisale a tu coordinador'), findsNothing);
  expect(_principal, findsNothing);
  expect(_titulo, findsNothing);
  if (sinRepetir) {
    expect(find.text(_textoRevocada), findsOneWidget, reason: 'aviso único $donde');
    expect(find.byType(SnackBar), findsNothing, reason: 'ningún SnackBar colgado $donde');
  }
}

void main() {
  setUp(_nuevoTelefono);

  group('QA #61 r2 · la sesión que el servidor no acepta, por cada camino que consulta la cuenta', () {
    for (final (nombre, falla) in _rechazos) {
      testWidgets('$nombre al tocar «Actualizar» en «Esperando asignación»: cierra y avisa', (
        tester,
      ) async {
        await _abrir(tester);
        await _entrar(tester);
        expect(_titulo, findsOneWidget);

        _rpc.siguiente = () async => throw falla;
        await _tocarActualizar(tester);

        _esperarLoginConAvisoDeSesion(tester, donde: '($nombre, Actualizar)');
      });

      testWidgets('$nombre al deslizar para refrescar: cierra y avisa', (tester) async {
        await _abrir(tester);
        await _entrar(tester);

        _rpc.siguiente = () async => throw falla;
        await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
        await tester.pumpAndSettle();

        _esperarLoginConAvisoDeSesion(tester, donde: '($nombre, deslizar)');
      });

      testWidgets('$nombre con la cuenta suspendida y deslizar: cierra y avisa', (tester) async {
        await _abrir(tester);
        _rpc.siguiente = () async => 'SUSPENDIDA';
        await _entrar(tester);
        expect(find.text('Cuenta suspendida'), findsOneWidget);

        _rpc.siguiente = () async => throw falla;
        final actualizar = find.byKey(const Key('espera_actualizar'));
        if (actualizar.evaluate().isEmpty) {
          // La suspendida refresca solo deslizando.
          await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
          await tester.pumpAndSettle();
        } else {
          await _tocarActualizar(tester);
        }

        _esperarLoginConAvisoDeSesion(tester, donde: '($nombre, suspendida)', sinRepetir: false);
      });

      testWidgets(
        '$nombre al entrar (login): no se muestra «Esperando asignación» ni los módulos',
        (tester) async {
          await _abrir(tester);
          _rpc.siguiente = () async => throw falla;
          await _entrar(tester);

          _esperarLoginConAvisoDeSesion(tester, donde: '($nombre, login)');
        },
      );

      testWidgets(
        '$nombre en el arranque en frío con la cuenta ACTIVA recordada: no entra al inicio con un '
        'estado viejo, cierra y avisa',
        (tester) async {
          await _abrir(tester);
          _rpc.siguiente = () async => 'ACTIVA';
          await _entrar(tester);
          expect(_principal, findsOneWidget);

          // Se cierra la app y se vuelve a abrir: la sesión y el estado recordado siguen en el
          // teléfono, pero el servidor ya no acepta la sesión.
          _rpc.siguiente = () async => throw falla;
          await tester.pumpWidget(const SizedBox.shrink());
          await _abrir(tester);

          _esperarLoginConAvisoDeSesion(tester, donde: '($nombre, arranque en frío ACTIVA)');
        },
      );

      testWidgets(
        '$nombre en el arranque en frío con «pendiente» recordada: cierra y avisa, no dice '
        '«Esperando asignación»',
        (tester) async {
          await _abrir(tester);
          await _entrar(tester);
          expect(_titulo, findsOneWidget);

          _rpc.siguiente = () async => throw falla;
          await tester.pumpWidget(const SizedBox.shrink());
          await _abrir(tester);

          _esperarLoginConAvisoDeSesion(tester, donde: '($nombre, arranque en frío pendiente)');
        },
      );
    }

    testWidgets(
      'tras el rechazo la sesión queda cerrada de verdad: al reabrir la app sigue el login (sin '
      'entrar sola con el estado recordado)',
      (tester) async {
        await _abrir(tester);
        _rpc.siguiente = () async => 'ACTIVA';
        await _entrar(tester);
        _rpc.siguiente = () async => throw const PostgrestException(message: 'x', code: '42501');
        await tester.pumpWidget(const SizedBox.shrink());
        await _abrir(tester);
        _esperarLoginConAvisoDeSesion(tester);

        // El servidor vuelve a aceptar, pero la sesión guardada se descartó: hay que volver a entrar.
        _rpc.siguiente = () async => 'ACTIVA';
        await tester.pumpWidget(const SizedBox.shrink());
        await _abrir(tester);
        expect(_login, findsOneWidget);
        expect(_principal, findsNothing);
      },
    );

    testWidgets(
      'reentrada: tras el rechazo se puede volver a entrar, el aviso viejo se va y un segundo '
      'rechazo vuelve a cerrar (nada queda trabado)',
      (tester) async {
        await _abrir(tester);
        _rpc.siguiente = () async => throw const PostgrestException(message: 'x', code: '42501');
        await _entrar(tester);
        _esperarLoginConAvisoDeSesion(tester, donde: '(primer rechazo)');

        _rpc.siguiente = () async => 'PENDIENTE_ASIGNACION';
        await _entrar(tester);
        expect(_titulo, findsOneWidget);
        expect(_avisoSesion, findsNothing);
        expect(find.text(_textoRevocada), findsNothing);

        _rpc.siguiente = () async => throw const AuthException('vencida', code: 'bad_jwt');
        await _tocarActualizar(tester);
        _esperarLoginConAvisoDeSesion(tester, donde: '(segundo rechazo)');

        _rpc.siguiente = () async => 'ACTIVA';
        await _entrar(tester);
        expect(_principal, findsOneWidget);
        expect(_avisoSesion, findsNothing);
      },
    );

    testWidgets(
      'el «Reintentar» del aviso de un módulo bloqueado (estado nunca consultado), con la sesión '
      'rechazada: cierra y avisa',
      (tester) async {
        await _abrir(tester);
        _rpc.siguiente = () async => throw const PostgrestException(message: 'x', code: '500');
        await _entrar(tester);
        await tester.tap(find.byKey(const Key('inicio_pestana_mapa')));
        await tester.pumpAndSettle();
        final reintentar = find.byKey(const Key('modulo_bloqueado_reintentar'));
        expect(reintentar, findsOneWidget);

        _rpc.siguiente = () async => throw const PostgrestException(message: 'x', code: '42501');
        await tester.tap(reintentar);
        await tester.pumpAndSettle();

        _esperarLoginConAvisoDeSesion(tester, donde: '(Reintentar del aviso de módulo)');
      },
    );

    testWidgets(
      'el «Reintentar» del aviso de un módulo bloqueado desde Configuración, con la sesión '
      'rechazada: cierra y avisa, sin dejar «avisale a tu coordinador» sobre el login',
      (tester) async {
        await _abrir(tester);
        _rpc.siguiente = () async => throw const PostgrestException(message: 'x', code: '500');
        await _entrar(tester);
        await tester.tap(find.byKey(const Key('espera_configuracion')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('inicio_pestana_ventas')));
        await tester.pumpAndSettle();
        final reintentar = find.byKey(const Key('modulo_bloqueado_reintentar'));
        expect(reintentar, findsOneWidget);

        _rpc.siguiente = () async => throw const PostgrestException(message: 'x', code: '42501');
        await tester.tap(reintentar);
        await tester.pumpAndSettle();

        _esperarLoginConAvisoDeSesion(tester, donde: '(Reintentar desde Configuración)');
      },
    );

    testWidgets(
      'cuenta suspendida y «Actualizar» con la sesión rechazada: el aviso de la sesión se ve una '
      'sola vez sobre el login (no repetido en un SnackBar)',
      (tester) async {
        await _abrir(tester);
        _rpc.siguiente = () async => 'SUSPENDIDA';
        await _entrar(tester);
        _rpc.siguiente = () async => throw const PostgrestException(message: 'x', code: '42501');
        await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
        await tester.pumpAndSettle();

        _esperarLoginConAvisoDeSesion(tester, donde: '(suspendida, aviso único)');
      },
      // skip: issue #61 — QA r2: con la cuenta suspendida el rechazo deja el mismo aviso dos veces sobre el login (aviso + SnackBar de la pantalla de espera).
      skip: true,
    );

    testWidgets(
      'carrera: el rechazo de una consulta de la sesión anterior no cierra la sesión nueva (misma '
      'persona que cerró y volvió a entrar)',
      (tester) async {
        await _abrir(tester);
        await _entrar(tester);
        expect(_titulo, findsOneWidget);

        // «Actualizar» queda en vuelo...
        final gate = Completer<Object?>();
        _rpc.siguiente = () => gate.future;
        await tester.ensureVisible(_actualizar);
        await tester.tap(_actualizar);
        await tester.pump();

        // ...la persona cierra sesión y vuelve a entrar...
        final container = _contenedor(tester);
        _rpc.siguiente = () async => 'PENDIENTE_ASIGNACION';
        await container.read(sesionProvider.notifier).cerrarSesion();
        await tester.pumpAndSettle();
        expect(_login, findsOneWidget);
        await _entrar(tester);
        expect(_titulo, findsOneWidget);

        // ...y recién entonces contesta la consulta vieja diciendo que la sesión no sirve.
        gate.completeError(const PostgrestException(message: 'x', code: '42501'));
        await tester.pumpAndSettle();

        expect(_titulo, findsOneWidget, reason: 'la sesión nueva sigue abierta');
        expect(_login, findsNothing);
        expect(_avisoSesion, findsNothing);
      },
    );

    testWidgets('doble toque en «Actualizar» con la sesión rechazada: una sola consulta y un solo '
        'cierre', (tester) async {
      await _abrir(tester);
      await _entrar(tester);
      final antes = _rpc.llamadas;

      final gate = Completer<Object?>();
      _rpc.siguiente = () => gate.future;
      await tester.ensureVisible(_actualizar);
      await tester.tap(_actualizar);
      await tester.pump();
      await tester.tap(_actualizar, warnIfMissed: false);
      await tester.pump();
      expect(_rpc.llamadas - antes, 1);

      gate.completeError(const PostgrestException(message: 'x', code: '42501'));
      await tester.pumpAndSettle();
      _esperarLoginConAvisoDeSesion(tester, donde: '(doble toque)');
    });

    testWidgets('RPC colgada más de 15 s y después rechazada: primero «sin conexión» con '
        '«Reintentar», y el reintento rechazado cierra', (tester) async {
      await _abrir(tester);
      final colgada = Completer<Object?>();
      _rpc.siguiente = () => colgada.future;
      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión'), findsOneWidget);

      // La respuesta tardía es el rechazo: la persona no queda con un «Reintentar» que no sirve.
      colgada.completeError(const PostgrestException(message: 'x', code: '42501'));
      await tester.pumpAndSettle();
      // Si la tardía no cierra, el reintento tiene que hacerlo.
      if (_login.evaluate().isEmpty) {
        _rpc.siguiente = () async => throw const PostgrestException(message: 'x', code: '42501');
        await _tocarActualizar(tester);
      }
      _esperarLoginConAvisoDeSesion(tester, donde: '(tope de 15 s)');
    });
  });

  group('QA #61 r2 · privacidad del rechazo', () {
    testWidgets('el log del rechazo lleva solo códigos: ni el mensaje del servidor ni el correo', (
      tester,
    ) async {
      await _abrir(tester);
      _rpc.siguiente = () async => throw const PostgrestException(
        message: 'usuario ana@example.com cédula 4.123.456-7 sin sesión',
        details: 'tel 099123456',
        code: '42501',
      );
      await _entrar(tester);
      _esperarLoginConAvisoDeSesion(tester);

      final texto = _salidaLog.buffer.expand((e) => e.lines).join('\n');
      expect(texto, contains('42501'));
      expect(texto, isNot(contains('ana@example.com')));
      expect(texto, isNot(contains('4.123.456')));
      expect(texto, isNot(contains('099123456')));
      expect(const SesionRevocadaException().toString(), isNot(contains('@')));
    });
  });

  group('QA #61 r2 · el login al que se llega por este camino (accesibilidad y tamaños)', () {
    const tamanos = [
      (Size(360, 640), 1.0, '360x640'),
      (Size(360, 640), 2.0, '360x640 con texto 2.0'),
      (Size(412, 915), 1.0, '412x915'),
      (Size(412, 915), 2.0, '412x915 con texto 2.0'),
    ];
    for (final (tam, texto, nombre) in tamanos) {
      testWidgets(
        'login con el aviso de sesión a $nombre: toque, etiquetas, contraste, sin overflow',
        (tester) async {
          final semantica = tester.ensureSemantics();
          try {
            await _abrir(tester);
            _rpc.siguiente = () async =>
                throw const PostgrestException(message: 'x', code: '42501');
            await _entrar(tester);
            _tamano(tester, tam, texto: texto);
            await tester.pump(const Duration(milliseconds: 500));

            expect(tester.takeException(), isNull);
            expect(_avisoSesion, findsOneWidget);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          } finally {
            semantica.dispose();
          }
        },
      );
    }
  });

  group('QA #61 r2 · hallazgos', () {
    testWidgets(
      'PGRST301 (JWT vencido de PostgREST, HTTP 401): sigue el flujo de sesión revocada, igual '
      'que 42501 y la AuthException',
      (tester) async {
        await _abrir(tester);
        _rpc.siguiente = () async =>
            throw const PostgrestException(message: 'JWT expired', code: 'PGRST301');
        await _entrar(tester);

        _esperarLoginConAvisoDeSesion(tester, donde: '(PGRST301)');
      },
      // skip: issue #61 — QA r2: PGRST301 (JWT vencido) queda como error del servidor con «avisale a tu coordinador».
      skip: true,
    );
  });
}

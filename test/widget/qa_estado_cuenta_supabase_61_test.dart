// QA de #61 / PR #495 (HU-AUTH-008): la fuente real del estado de cuenta, la RPC `estado_cuenta()`
// de Supabase. La vista 18 no cambia; lo que se prueba es que, con la fuente REAL puesta en la app
// (no el fake en memoria), cada respuesta del servidor llega a la pantalla que la HU promete y
// cada falla tiene salida:
//  1. el cliente de Supabase de verdad (HTTP simulado): ruta, método, cuerpo del servidor, errores;
//  2. la app entera sobre `EstadoCuentaSupabase` con una RPC guionada: login, refrescar, sin
//     conexión, error del servidor, valor desconocido, tope de 15 s, doble toque;
//  3. el log: solo códigos, nunca el cuerpo ni el mensaje del servidor.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_remote_data_source_supabase.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/asignacion_campania_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/logger_mudo.dart';

// ---------------------------------------------------------------------------------------------
// 1. El cliente de Supabase de verdad, con el HTTP simulado
// ---------------------------------------------------------------------------------------------

/// Un servidor de pega: devuelve lo que se le pida y anota cada pedido.
final class _Servidor {
  _Servidor(this.responder);

  Future<http.Response> Function(http.Request) responder;
  final pedidos = <http.Request>[];

  SupabaseClient cliente() => SupabaseClient(
    'http://localhost:54321',
    'anon-key-de-prueba',
    httpClient: MockClient((req) async {
      pedidos.add(req);
      final r = await responder(req);
      // postgrest lee `response.request`: el cliente real de http siempre lo trae.
      return http.Response.bytes(r.bodyBytes, r.statusCode, request: req, headers: r.headers);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  Future<EstadoCuenta> consultar({AppLogger? logger}) =>
      EstadoCuentaSupabase.conCliente(cliente(), logger: logger ?? loggerMudo()).consultar();
}

http.Response _json(int status, Object? cuerpo) => http.Response(
  jsonEncode(cuerpo),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Matcher _servidorConStatus(int? status) =>
    isA<ServidorException>().having((e) => e.status, 'status', status);

// ---------------------------------------------------------------------------------------------
// 2. La app entera sobre EstadoCuentaSupabase con una RPC guionada
// ---------------------------------------------------------------------------------------------

/// La RPC guionada: cada llamada toma lo que corresponda del guion; sin guion, la respuesta fija.
final class _Rpc {
  /// Lo que contesta la próxima llamada: un valor, o una función que lo produce (puede fallar).
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

final _titulo = find.byKey(const Key('espera_titulo'));
final _actualizar = find.byKey(const Key('espera_actualizar'));
final _principal = find.byKey(const Key('inicio_principal'));
final _login = find.byKey(const Key('login_enviar'));
final _sinConexion = find.byKey(const Key('espera_sin_conexion'));
final _error = find.byKey(const Key('espera_error'));

const _textoSinConexion =
    'No hay conexión para revisar tu cuenta. Conectate a internet y tocá Reintentar.';
const _textoError =
    'No pudimos consultar el estado de tu cuenta. Tocá Reintentar para probar de nuevo; si sigue '
    'pasando, avisale a tu coordinador.';

late _Rpc _rpc;
late EstadoCuentaLocalEnMemoria _recordado;
late MemoryOutput _salidaLog;

Future<void> _montar(WidgetTester tester) async {
  _rpc = _Rpc();
  _recordado = EstadoCuentaLocalEnMemoria();
  _salidaLog = MemoryOutput();
  final fuente = EstadoCuentaSupabase(
    _rpc.llamar,
    logger: AppLogger(
      logger: Logger(level: Level.debug, printer: _PlanoSimple(), output: _salidaLog),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
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

/// Imprime solo el mensaje de cada evento (ya trae el formato del proyecto).
final class _PlanoSimple extends LogPrinter {
  @override
  List<String> log(LogEvent event) => ['${event.message}'];
}

String _usuarioId(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ColportoresApp)),
).read(sesionProvider).value!.usuarioId;

Future<void> _entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
  await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
  await tester.tap(_login);
  await tester.pumpAndSettle();
}

Future<void> _tocarReintentar(WidgetTester tester) async {
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

void main() {
  group('QA #61 · cliente real de Supabase: lo que sale y lo que se entiende', () {
    test(
      'Dado un servidor que contesta, la app llama POST /rest/v1/rpc/estado_cuenta sin datos',
      () async {
        final servidor = _Servidor((_) async => _json(200, 'ACTIVA'));

        expect(await servidor.consultar(), EstadoCuenta.activa);

        expect(servidor.pedidos, hasLength(1));
        final pedido = servidor.pedidos.single;
        expect(pedido.method, 'POST');
        expect(pedido.url.path, '/rest/v1/rpc/estado_cuenta');
        expect(pedido.headers['apikey'], 'anon-key-de-prueba');
        // El estado lo decide el servidor por el JWT: la app no manda nada de la persona.
        expect(pedido.body, anyOf(isEmpty, '{}', 'null'));
        expect(pedido.url.query, isEmpty);
      },
    );

    for (final (cuerpo, esperado) in <(String, EstadoCuenta)>[
      ('ACTIVA', EstadoCuenta.activa),
      ('PENDIENTE_ASIGNACION', EstadoCuenta.pendienteAsignacion),
      ('SUSPENDIDA', EstadoCuenta.suspendida),
    ]) {
      test('cuando PostgREST devuelve el texto JSON "$cuerpo", entonces es $esperado', () async {
        final servidor = _Servidor((_) async => _json(200, cuerpo));
        expect(await servidor.consultar(), esperado);
      });
    }

    test(
      'cuando el cuerpo es texto plano sin comillas (ACTIVA), igual se entiende o no afirma nada',
      () async {
        final servidor = _Servidor(
          (_) async => http.Response('ACTIVA', 200, headers: {'content-type': 'text/plain'}),
        );
        // Nunca puede salir otra cosa que activa o una falla del servidor controlada.
        try {
          expect(await servidor.consultar(), EstadoCuenta.activa);
        } on ServidorException catch (e) {
          expect(e.status, 200);
        }
      },
    );

    for (final cuerpo in <String>[
      '',
      'null',
      '[]',
      '{}',
      '"soft_deleted"',
      '"SOFT_DELETED"',
      '7',
      '<html>Iniciá sesión en la red WiFi</html>',
    ]) {
      test('cuando el servidor contesta 200 con "$cuerpo", no afirma nada de la cuenta', () async {
        final servidor = _Servidor(
          (_) async => http.Response(cuerpo, 200, headers: {'content-type': 'application/json'}),
        );
        await expectLater(
          servidor.consultar(),
          throwsA(anyOf(_servidorConStatus(200), isA<ServidorException>())),
        );
      });
    }

    test('42501 (sin sesión válida): HTTP 403 con el código en el cuerpo → error 401', () async {
      final servidor = _Servidor(
        (_) async => _json(403, {
          'code': '42501',
          'message': 'estado_cuenta requiere un usuario autenticado',
          'details': null,
          'hint': null,
        }),
      );
      await expectLater(servidor.consultar(), throwsA(_servidorConStatus(401)));
    });

    test('P0002 (usuario sin perfil): HTTP 404 → error 404', () async {
      final servidor = _Servidor(
        (_) async => _json(404, {
          'code': 'P0002',
          'message': 'el usuario autenticado no tiene perfil en public.usuario',
        }),
      );
      await expectLater(servidor.consultar(), throwsA(_servidorConStatus(404)));
    });

    test(
      'el SQLSTATE de la base (57014, statement_timeout) no se lleva como si fuera un status HTTP',
      () async {
        final servidor = _Servidor(
          (_) async => _json(500, {'code': '57014', 'message': 'canceling statement'}),
        );
        await expectLater(
          servidor.consultar(),
          throwsA(isA<ServidorException>().having((e) => e.status, 'status', isNot(57014))),
        );
      },
    );

    test(
      'ningún SQLSTATE numérico (23505, 57014) se toma por status; el log lo dice como code',
      () async {
        for (final sqlstate in ['23505', '57014', '40001']) {
          final servidor = _Servidor((_) async => _json(500, {'code': sqlstate, 'message': 'x'}));
          await expectLater(servidor.consultar(), throwsA(_servidorConStatus(null)));
        }
      },
    );

    test(
      'JWT vencido (PGRST301, HTTP 401) es un error del servidor con salida (Reintentar)',
      () async {
        final servidor = _Servidor(
          (_) async => _json(401, {'code': 'PGRST301', 'message': 'JWT expired'}),
        );
        await expectLater(servidor.consultar(), throwsA(isA<ServidorException>()));
      },
    );

    test('gateway caído con HTML (HTTP 502/503): error del servidor, no sin conexión', () async {
      for (final status in [502, 503]) {
        final servidor = _Servidor(
          (_) async => http.Response(
            '<html>Bad gateway</html>',
            status,
            headers: {'content-type': 'text/html'},
          ),
        );
        await expectLater(servidor.consultar(), throwsA(_servidorConStatus(status)));
      }
    });

    test('statement_timeout del servidor (57014, HTTP 500) es un error del servidor', () async {
      final servidor = _Servidor(
        (_) async => _json(500, {'code': '57014', 'message': 'canceling statement'}),
      );
      await expectLater(servidor.consultar(), throwsA(isA<ServidorException>()));
    });

    final redes = <String, Object>{
      'SocketException': const SocketException('Failed host lookup'),
      'HandshakeException': const HandshakeException('certificado'),
      'ClientException': http.ClientException('Connection closed before full header was received'),
      'TimeoutException': TimeoutException('lento'),
    };
    redes.forEach((nombre, falla) {
      test('$nombre en el transporte real → sin conexión (no error del servidor)', () async {
        final servidor = _Servidor((_) async => throw falla);
        await expectLater(servidor.consultar(), throwsA(isA<SinConexionException>()));
      });
    });

    test(
      'dos pedidos seguidos del mismo cliente: cada uno llega al servidor y se resuelve solo',
      () async {
        var n = 0;
        final servidor = _Servidor(
          (_) async => _json(200, ++n == 1 ? 'PENDIENTE_ASIGNACION' : 'ACTIVA'),
        );
        final fuente = EstadoCuentaSupabase.conCliente(servidor.cliente(), logger: loggerMudo());
        final a = fuente.consultar();
        final b = fuente.consultar();
        final resultados = await Future.wait([a, b]);
        expect(servidor.pedidos, hasLength(2));
        expect(resultados.toSet(), {EstadoCuenta.pendienteAsignacion, EstadoCuenta.activa});
      },
    );
  });

  group('QA #61 · privacidad: el log lleva códigos, nunca el cuerpo ni la persona', () {
    test('un error con datos de la persona en el mensaje no llega al log ni a toString', () async {
      final salida = MemoryOutput();
      final logger = AppLogger(
        logger: Logger(level: Level.debug, printer: _PlanoSimple(), output: salida),
      );
      final fuente = EstadoCuentaSupabase(
        () async => throw const PostgrestException(
          message: 'lucia.perez@ejemplo.uy 099123456',
          details: 'Lucía Pérez',
          hint: 'cédula 1.234.567-8',
          code: '500',
        ),
        logger: logger,
      );
      Object? atrapada;
      try {
        await fuente.consultar();
      } on Object catch (e) {
        atrapada = e;
      }
      final texto = salida.buffer.expand((e) => e.lines).join('\n');
      expect(texto, isNotEmpty);
      for (final pii in ['lucia', 'ejemplo.uy', '099123456', 'Lucía', 'cédula']) {
        expect(texto, isNot(contains(pii)));
        expect('$atrapada', isNot(contains(pii)));
      }
    });

    test('un valor desconocido con datos adentro no se escribe en el log (solo el tipo)', () async {
      final salida = MemoryOutput();
      final logger = AppLogger(
        logger: Logger(level: Level.debug, printer: _PlanoSimple(), output: salida),
      );
      final fuente = EstadoCuentaSupabase(() async => 'lucia@ejemplo.uy', logger: logger);
      await expectLater(fuente.consultar(), throwsA(isA<ServidorException>()));
      final texto = salida.buffer.expand((e) => e.lines).join('\n');
      expect(texto, isNotEmpty);
      expect(texto, isNot(contains('lucia')));
    });

    test('la AuthException no vuelca su mensaje al log', () async {
      final salida = MemoryOutput();
      final logger = AppLogger(
        logger: Logger(level: Level.debug, printer: _PlanoSimple(), output: salida),
      );
      final fuente = EstadoCuentaSupabase(
        () async => throw const AuthException('token de lucia@ejemplo.uy vencido', code: 'bad_jwt'),
        logger: logger,
      );
      await expectLater(fuente.consultar(), throwsA(_servidorConStatus(401)));
      final texto = salida.buffer.expand((e) => e.lines).join('\n');
      expect(texto, contains('bad_jwt'));
      expect(texto, isNot(contains('lucia')));
    });
  });

  group('QA #61 · la app entera sobre la fuente real (HU-AUTH-008, textos literales)', () {
    testWidgets('Escenario: login con cuenta en PENDIENTE_ASIGNACION → «Esperando asignación», '
        'sin módulos de campo', (tester) async {
      await _montar(tester);
      _rpc.siguiente = () async => 'PENDIENTE_ASIGNACION';
      await _entrar(tester);

      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(_principal, findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
      expect(_rpc.llamadas, 1);
    });

    testWidgets(
      'Escenario: pull-to-refresh / «Actualizar» — sigue pendiente muestra «Aún no asignado»; '
      'si pasó a ACTIVA navega a la pantalla principal',
      (tester) async {
        await _montar(tester);
        await _entrar(tester);

        await _tocarReintentar(tester);
        expect(find.text('Aún no asignado'), findsOneWidget);
        expect(_principal, findsNothing);

        _rpc.siguiente = () async => 'ACTIVA';
        await _tocarReintentar(tester);
        expect(_principal, findsOneWidget);
        expect(_titulo, findsNothing);
      },
    );

    testWidgets('el pull-to-refresh (deslizar) también consulta la RPC y avanza a ACTIVA', (
      tester,
    ) async {
      await _montar(tester);
      await _entrar(tester);
      final antes = _rpc.llamadas;

      _rpc.siguiente = () async => 'ACTIVA';
      await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(_rpc.llamadas, antes + 1);
      expect(_principal, findsOneWidget);
    });

    testWidgets('cuenta SUSPENDIDA: literal de la HU y salida a Configuración', (tester) async {
      await _montar(tester);
      _rpc.siguiente = () async => 'SUSPENDIDA';
      await _entrar(tester);

      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(find.text('Tu cuenta está suspendida. Contactá al administrador.'), findsOneWidget);
      expect(find.byKey(const Key('espera_ir_a_configuracion')), findsOneWidget);
      expect(_principal, findsNothing);
    });

    testWidgets(
      'Escenario: sin conexión y estado nunca consultado → aviso de sin conexión con la acción, '
      'sin afirmar «Esperando asignación»',
      (tester) async {
        await _montar(tester);
        _rpc.siguiente = () async => throw const SocketException('sin ruta');
        await _entrar(tester);

        expect(find.text('Sin conexión'), findsOneWidget);
        expect(find.text(_textoSinConexion), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.textContaining('Esperando asignación'), findsNothing);
        expect(find.textContaining('Tu cuenta fue creada'), findsNothing);
        expect(_principal, findsNothing);
        expect(_error, findsNothing);
      },
    );

    testWidgets(
      'error del servidor (HTTP 503 de PostgREST): texto de la HU, con «Reintentar», sin afirmar nada',
      (tester) async {
        await _montar(tester);
        _rpc.siguiente = () async => throw const PostgrestException(message: 'x', code: '503');
        await _entrar(tester);

        expect(_error, findsOneWidget);
        expect(find.text(_textoError), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.textContaining('Esperando asignación'), findsNothing);
        expect(_principal, findsNothing);
        expect(_sinConexion, findsNothing);
      },
    );

    for (final (nombre, falla) in <(String, Object)>[
      ('42501 (sesión no válida)', const PostgrestException(message: 'x', code: '42501')),
      ('P0002 (sin perfil)', const PostgrestException(message: 'x', code: 'P0002')),
      ('AuthException de la sesión', const AuthException('vencida', code: 'bad_jwt')),
    ]) {
      testWidgets('$nombre: aviso de error con «Reintentar» (el usuario tiene salida)', (
        tester,
      ) async {
        await _montar(tester);
        _rpc.siguiente = () async => throw falla;
        await _entrar(tester);

        expect(find.text(_textoError), findsOneWidget);
        expect(_actualizar, findsOneWidget);
        expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);
        expect(_principal, findsNothing);
      });
    }

    for (final raro in <Object?>['SOFT_DELETED', 'activa', '', null, 7]) {
      testWidgets('valor desconocido del servidor ($raro): ni entra ni dice «Esperando»', (
        tester,
      ) async {
        await _montar(tester);
        _rpc.siguiente = () async => raro;
        await _entrar(tester);

        expect(find.text(_textoError), findsOneWidget);
        expect(find.textContaining('Esperando asignación'), findsNothing);
        expect(_principal, findsNothing);
        expect(await _recordado.leer(_usuarioId(tester)), isNull);
      });
    }

    testWidgets(
      'falla a mitad de la acción: tras un error el botón vuelve a habilitarse y el reintento '
      'con red avanza',
      (tester) async {
        await _montar(tester);
        _rpc.siguiente = () async => throw const SocketException('sin ruta');
        await _entrar(tester);
        expect(find.text(_textoSinConexion), findsOneWidget);

        // Segunda falla, de otro tipo: el aviso cambia a su causa y el botón sigue vivo.
        _rpc.siguiente = () async => throw const PostgrestException(message: 'x', code: '500');
        await _tocarReintentar(tester);
        expect(find.text(_textoError), findsOneWidget);
        expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);

        _rpc.siguiente = () async => 'ACTIVA';
        await _tocarReintentar(tester);
        expect(_principal, findsOneWidget);
      },
    );

    testWidgets(
      'la RPC que no contesta: a los 15 s se trata como sin conexión, con «Reintentar» a mano',
      (tester) async {
        await _montar(tester);
        final colgada = Completer<Object?>();
        _rpc.siguiente = () => colgada.future;
        await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
        await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
        await tester.tap(_login);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Mientras espera, la pantalla dice qué está haciendo (nunca un spinner mudo).
        expect(find.text('Revisando con el servidor…'), findsWidgets);

        await tester.pump(const Duration(seconds: 16));
        await tester.pumpAndSettle();
        expect(find.text('Sin conexión'), findsOneWidget);
        expect(find.text(_textoSinConexion), findsOneWidget);
        expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);
        expect(find.textContaining('Revisando con el servidor'), findsNothing);

        // Reintento a mano con red: la RPC contesta y la pantalla avanza.
        _rpc.siguiente = () async => 'ACTIVA';
        await _tocarReintentar(tester);
        expect(_principal, findsOneWidget);

        colgada.complete('PENDIENTE_ASIGNACION');
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'doble toque en «Reintentar» mientras la RPC está en vuelo: no se pisan ni queda trabado',
      (tester) async {
        await _montar(tester);
        _rpc.siguiente = () async => throw const SocketException('sin ruta');
        await _entrar(tester);
        final antes = _rpc.llamadas;

        final gate = Completer<Object?>();
        _rpc.siguiente = () => gate.future;
        await tester.ensureVisible(_actualizar);
        await tester.tap(_actualizar);
        await tester.pump();
        await tester.tap(_actualizar, warnIfMissed: false);
        await tester.pump();

        expect(_rpc.llamadas - antes, 1, reason: 'el segundo toque no dispara otra consulta');

        gate.complete('ACTIVA');
        await tester.pumpAndSettle();
        expect(_principal, findsOneWidget);
      },
    );

    testWidgets(
      'estado ya recordado + sin red al reabrir: rige el último conocido (la fuente real no lo '
      'pisa con una falla)',
      (tester) async {
        await _montar(tester);
        await _entrar(tester);
        expect(find.text('Esperando asignación'), findsOneWidget);
        expect(await _recordado.leer(_usuarioId(tester)), EstadoCuenta.pendienteAsignacion);

        _rpc.siguiente = () async => throw const SocketException('sin ruta');
        await _tocarReintentar(tester);

        // Había un estado conocido: sigue «Esperando asignación», con aviso de sin conexión, no
        // el genérico ni una pantalla vacía.
        expect(find.text('Esperando asignación'), findsOneWidget);
        expect(_principal, findsNothing);
      },
    );
  });

  group('QA #61 · tamaños y accesibilidad con la fuente real (vista 18 sin cambios)', () {
    const tamanos = [
      (Size(360, 640), 1.0, '360x640'),
      (Size(360, 640), 2.0, '360x640 con texto 2.0'),
      (Size(412, 915), 1.0, '412x915'),
      (Size(412, 915), 2.0, '412x915 con texto 2.0'),
    ];
    final variantes = <String, Future<Object?> Function()>{
      'pendiente': () async => 'PENDIENTE_ASIGNACION',
      'sin-conexion': () async => throw const SocketException('sin ruta'),
      'error-servidor': () async => throw const PostgrestException(message: 'x', code: '500'),
      'valor-desconocido': () async => 'SOFT_DELETED',
      'suspendida': () async => 'SUSPENDIDA',
    };
    for (final (tam, texto, nombre) in tamanos) {
      variantes.forEach((variante, respuesta) {
        testWidgets('$variante a $nombre: toque, etiquetas, contraste y sin overflow', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          try {
            await _montar(tester);
            _rpc.siguiente = respuesta;
            await _entrar(tester);
            _tamano(tester, tam, texto: texto);
            await tester.pump(const Duration(milliseconds: 500));

            expect(tester.takeException(), isNull, reason: '$variante a $nombre');
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          } finally {
            semantica.dispose();
          }
        });
      });
    }
  });
}

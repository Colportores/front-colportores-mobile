// QA de HU-NOT-001 / #414 («Token FCM»): casos límite, privacidad y los dos hallazgos del QA.
// Sin vista (nota de 24A·05): el QA es de comportamiento, no de pantalla. Los tests con `skip`
// documentan hallazgos; el implementador saca el `skip` cuando los arregla.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/push_remotas_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/token_push_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/token_push_repository.dart';
import 'package:colportores_mobile/features/notificaciones/domain/services/registro_token_push.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/registro_token_push_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../helpers/recuperacion_arnes.dart' show ConexionControlable;

final class _Salida extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void _volverALaApp(TestWidgetsFlutterBinding binding) {
  for (final estado in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    binding.handleAppLifecycleStateChanged(estado);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('QA #414 · registro (dominio)', () {
    late TokenPushEnMemoria servidor;
    late String? tokenDelSistema;
    late Object? fallaDelSistema;
    late RegistroTokenPush registro;
    late _Salida salida;

    setUp(() {
      servidor = TokenPushEnMemoria();
      tokenDelSistema = 'token-1';
      fallaDelSistema = null;
      salida = _Salida();
      registro = RegistroTokenPush(
        servidor: servidor,
        obtenerToken: () async {
          if (fallaDelSistema case final f?) throw f;
          return tokenDelSistema;
        },
        logger: AppLogger(
          logger: Logger(output: salida, printer: SimplePrinter()),
        ),
      );
    });

    group('privacidad: el token no va a los logs ni al toString', () {
      const secreto = 'fcm-token-secreto-AAA111';

      test('el sistema falla con un mensaje que trae el token: al log va solo el tipo', () async {
        fallaDelSistema = StateError(secreto);

        await registro.sincronizar();

        expect(registro.hayPendiente, isTrue);
        expect(salida.lineas, isNotEmpty, reason: 'la falla se loguea (sin el token)');
        expect(salida.lineas.join('\n'), isNot(contains(secreto)));
      });

      test('el servidor falla con un mensaje que trae el token: al log va solo el tipo', () async {
        tokenDelSistema = secreto;
        servidor.falla = const TokenPushServidorException(codigo: '23514');

        await registro.sincronizar();
        await registro.sincronizar(token: secreto);

        expect(salida.lineas.join('\n'), isNot(contains(secreto)));
        expect(salida.lineas.join('\n'), contains('23514'));
      });

      test('un error inesperado del servidor con el token en el mensaje no lo filtra', () async {
        final registroExplosivo = RegistroTokenPush(
          servidor: _ServidorQueLanza(StateError(secreto)),
          obtenerToken: () async => secreto,
          logger: AppLogger(
            logger: Logger(output: salida, printer: SimplePrinter()),
          ),
        );

        await registroExplosivo.sincronizar();
        await registroExplosivo.retirar();

        expect(salida.lineas.join('\n'), isNot(contains(secreto)));
      });

      test('toString de las excepciones y del registro no lleva el token', () async {
        tokenDelSistema = secreto;
        await registro.sincronizar();

        expect(registro.toString(), isNot(contains(secreto)));
        expect(const TokenPushSinConexionException().toString(), isNot(contains(secreto)));
        expect(const TokenPushServidorException(codigo: '42501').toString(), '''
TokenPushServidorException(42501)''');
        expect(servidor.toString(), isNot(contains(secreto)));
        expect(salida.lineas.join('\n'), isNot(contains(secreto)));
      });
    });

    group('datos límite', () {
      test('un token vacío del sistema o de una rotación no se sube ni queda pendiente', () async {
        tokenDelSistema = '';
        await registro.sincronizar();
        expect(servidor.pedidos, isEmpty);
        expect(registro.hayPendiente, isFalse);

        await registro.sincronizar(token: '');
        expect(servidor.pedidos, isEmpty);
        expect(registro.hayPendiente, isFalse);
      });

      test(
        'un token larguísimo con emoji se sube tal cual; si el servidor lo rechaza (23514) queda '
        'pendiente sin lanzar ni trabar',
        () async {
          final enorme = '${'ab😀' * 2000}-fin';
          servidor.falla = const TokenPushServidorException(codigo: '23514');

          await expectLater(registro.sincronizar(token: enorme), completes);

          expect(servidor.pedidos, [enorme]);
          expect(registro.hayPendiente, isTrue);

          servidor.falla = null;
          await registro.sincronizar(token: 'token-bueno');
          expect(servidor.guardado, 'token-bueno');
          expect(registro.hayPendiente, isFalse);
        },
      );

      test(
        'sesión sin token todavía (null) y luego llega una rotación: sube la rotación',
        () async {
          tokenDelSistema = null;
          await registro.sincronizar();
          expect(servidor.pedidos, isEmpty);

          await registro.sincronizar(token: 'token-recien-nacido');

          expect(servidor.guardado, 'token-recien-nacido');
        },
      );
    });

    group('acciones superpuestas y fallas a mitad', () {
      test('dos «retirar» a la vez (cerrar sesión y borrar datos): los dos terminan', () async {
        await registro.sincronizar();

        await expectLater(Future.wait([registro.retirar(), registro.retirar()]), completes);

        expect(servidor.guardado, isNull);
      });

      test(
        '42501 (sin sesión) a mitad: queda pendiente, nada trabado, el siguiente corre',
        () async {
          servidor.falla = const TokenPushServidorException(codigo: '42501');
          await registro.sincronizar();
          expect(registro.hayPendiente, isTrue);

          servidor.falla = null;
          await registro.sincronizarSiHaceFalta();

          expect(servidor.guardado, 'token-1');
          expect(registro.hayPendiente, isFalse);
        },
      );

      test(
        'el vacío que falla deja el token donde estaba y no impide el cierre ni uno nuevo',
        () async {
          await registro.sincronizar();
          servidor.falla = const TokenPushServidorException(codigo: '42501');

          await expectLater(registro.retirar(), completes);
          servidor.falla = null;
          await registro.sincronizar(token: 'token-2');

          expect(servidor.guardado, 'token-2');
        },
      );
    });

    group('HALLAZGOS', () {
      test(
        'H1: una subida lenta (más de 3 s) en curso al cerrar sesión no deja el token puesto '
        'después del vacío',
        () {
          fakeAsync((reloj) {
            servidor.demorado = Completer<void>();
            unawaited(registro.sincronizar());
            reloj.flushMicrotasks();

            unawaited(registro.retirar());
            reloj.elapse(const Duration(seconds: 4)); // el tope del retiro (3 s) ya pasó
            servidor.demorado!.complete(); // la subida lenta termina después
            reloj.flushMicrotasks();

            // El cierre de sesión ya siguió: el servidor tiene que quedar sin token (el vacío
            // llegó, o la subida tardía no llegó a escribirse).
            expect(servidor.guardado, isNull, reason: 'queda un token de una cuenta que cerró');
          });
        },
        skip:
            'QA #414: retirar() se rinde a los 3 s sin mandar el vacío si había una subida en '
            'curso, y esa subida deja el token puesto después de cerrar sesión',
      );

      test(
        'H2: terminado el vacío, volver a la app antes de que cierre la sesión no vuelve a '
        'subir el token',
        () async {
          await registro.sincronizar();
          await registro.retirar();
          expect(servidor.guardado, isNull);

          // La app vuelve al frente mientras el cierre de sesión todavía está en curso.
          await registro.sincronizarSiHaceFalta();

          expect(servidor.guardado, isNull, reason: 'el cierre fue a propósito: no re-registrar');
        },
        skip:
            'QA #414: retirar() deja _pendiente=true y _subidoEn=null aun si el vacío salió bien; '
            'un resume o un cambio de red antes de cerrar la sesión sube el token otra vez',
      );
    });
  });

  group('QA #414 · cableado (pantalla principal)', () {
    late PushRemotasEnMemoria push;
    late TokenPushEnMemoria servidor;
    late PermisoNotificacionesSistemaEnMemoria sistema;
    late ConexionControlable conexion;
    late ProviderSubscription<void> mirando;

    setUp(() {
      push = PushRemotasEnMemoria(token: 'token-1');
      servidor = TokenPushEnMemoria();
      sistema = PermisoNotificacionesSistemaEnMemoria();
      conexion = ConexionControlable();
    });

    Future<ProviderContainer> abrir() async {
      final c = ProviderContainer(
        overrides: [
          pushRemotasProvider.overrideWithValue(push),
          tokenPushRepositoryProvider.overrideWithValue(servidor),
          permisoNotificacionesSistemaProvider.overrideWithValue(sistema),
          monitorConectividadProvider.overrideWithValue(conexion),
          retiroTokenPushProvider.overrideWith(retirarTokenPush),
        ],
      );
      addTearDown(c.dispose);
      c.listen(notificacionesProvider, (_, _) {});
      mirando = c.listen(mantenerTokenPushProvider, (_, _) {});
      c.listen(conexionProvider, (_, _) {});
      await c.read(notificacionesProvider.future);
      await pumpEventQueue();
      return c;
    }

    test('reentrar a la pantalla principal tres veces no duplica oyentes: una rotación, una '
        'subida', () async {
      final c = await abrir();
      for (var i = 0; i < 3; i++) {
        mirando.close();
        await pumpEventQueue();
        mirando = c.listen(mantenerTokenPushProvider, (_, _) {});
        await pumpEventQueue();
      }
      push.rotaElToken('token-2');
      await pumpEventQueue();

      expect(servidor.pedidos.where((t) => t == 'token-2'), hasLength(1));
      expect(servidor.guardado, 'token-2');
    });

    test(
      'Firebase todavía sin token al abrir: no sube nada; cuando el sistema lo da, sube',
      () async {
        push.token = null;
        await abrir();
        expect(servidor.pedidos, isEmpty);

        push.rotaElToken('token-llegado');
        await pumpEventQueue();

        expect(servidor.guardado, 'token-llegado');
      },
    );

    test('iOS sin registrar al abrir (getToken lanza): queda pendiente y sube al volver a la '
        'app', () async {
      push.fallaAlObtenerToken = StateError('apns-token-not-set');
      await abrir();
      expect(servidor.pedidos, isEmpty);

      push.fallaAlObtenerToken = null;
      _volverALaApp(binding);
      await pumpEventQueue();

      expect(servidor.guardado, 'token-1');
    });

    test('permiso concedido y luego retirado en Configuración: no hay oyentes colgados ni '
        'subidas nuevas por rotaciones', () async {
      final c = await abrir();
      expect(servidor.guardado, 'token-1');

      sistema.estado = EstadoSistemaNotificaciones.apagadas;
      await c.read(notificacionesProvider.notifier).refrescar();
      await pumpEventQueue();
      push.rotaElToken('token-2');
      await pumpEventQueue();

      expect(servidor.pedidos, ['token-1'], reason: 'sin avisos activados no se sube nada nuevo');
    });

    test(
      'H2 (cableado): conexión que cambia de wifi a datos justo después del vacío no vuelve a '
      'subir el token',
      () async {
        final c = await abrir();
        await c.read(retiroTokenPushProvider)();
        expect(servidor.guardado, isNull);

        conexion.cambiarA(TipoConexion.datosMoviles);
        await pumpEventQueue();

        expect(servidor.guardado, isNull);
      },
      skip:
          'QA #414: retirar() deja _pendiente=true aun si el vacío salió bien; cualquier evento '
          'de conexión antes de cerrar la sesión sube el token otra vez',
    );
  });
}

final class _ServidorQueLanza implements TokenPushRepository {
  _ServidorQueLanza(this._error);
  final Object _error;

  @override
  Future<void> registrar(String? token) async => throw _error;
}

// HU-NOT-001 / #414 («Token FCM»): el cableado. Con el permiso dado el token sube; si el sistema lo
// rota se vuelve a subir; sin conexión queda pendiente y se sube al volver la señal o la app; y al
// cerrar sesión se vacía. El permiso apagado no sube nada.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/push_remotas_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/token_push_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/estado_notificaciones.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/token_push_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/registro_token_push_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/recuperacion_arnes.dart' show ConexionControlable;

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

  /// Lo que hace la pantalla principal: mirar el provider mientras haya sesión.
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

  group('al dar el permiso', () {
    test('con las notificaciones ya activadas, sube el token al abrir', () async {
      await abrir();

      expect(servidor.pedidos, ['token-1']);
      expect(servidor.guardado, 'token-1');
    });

    test('Escenario: Permisos concedidos — sin permiso no sube nada; al conceder, sube', () async {
      sistema.estado = EstadoSistemaNotificaciones.apagadas;
      final c = await abrir();
      expect(servidor.pedidos, isEmpty);
      expect(push.consultasDelToken, 0, reason: 'sin permiso ni se le pide el token al sistema');

      final resultado = await c.read(notificacionesProvider.notifier).activar();
      await pumpEventQueue();

      expect(resultado, ResultadoActivacion.activadas);
      expect(servidor.pedidos, ['token-1']);
    });

    test('con el permiso denegado no sube nada, tampoco al volver a la app', () async {
      sistema
        ..estado = EstadoSistemaNotificaciones.apagadas
        ..respuestaAlPedir = false;
      final c = await abrir();
      await c.read(notificacionesProvider.notifier).activar();
      _volverALaApp(binding);
      await pumpEventQueue();

      expect(servidor.pedidos, isEmpty);
    });

    test('un teléfono sin Firebase (sin token) sigue sin subir nada ni fallar', () async {
      push.token = null;
      await abrir();

      expect(push.consultasDelToken, 1);
      expect(servidor.pedidos, isEmpty);
    });

    test('doble toque en «Activar»: el token se sube una sola vez', () async {
      sistema.estado = EstadoSistemaNotificaciones.apagadas;
      final c = await abrir();

      final a = c.read(notificacionesProvider.notifier).activar();
      final b = c.read(notificacionesProvider.notifier).activar();
      await Future.wait([a, b]);
      await pumpEventQueue();

      expect(servidor.pedidos, ['token-1']);
    });
  });

  group('Escenario: Token rotado', () {
    test('sube el token nuevo', () async {
      await abrir();

      push.rotaElToken('token-2');
      await pumpEventQueue();

      expect(servidor.pedidos, ['token-1', 'token-2']);
      expect(servidor.guardado, 'token-2');
    });

    test(
      'dos rotaciones seguidas con el servidor lento: no se pierde ni se pisa ninguna',
      () async {
        await abrir();
        servidor.demorado = Completer<void>();

        push.rotaElToken('token-2');
        await pumpEventQueue();
        push.rotaElToken('token-3');
        await pumpEventQueue();
        servidor.demorado!.complete();
        await pumpEventQueue();

        expect(servidor.pedidos, ['token-1', 'token-2', 'token-3']);
        expect(servidor.guardado, 'token-3');
      },
    );

    test('una rotación que falla no traba las siguientes', () async {
      await abrir();
      servidor.falla = const TokenPushSinConexionException();
      push.rotaElToken('token-2');
      await pumpEventQueue();

      servidor.falla = null;
      push.rotaElToken('token-3');
      await pumpEventQueue();

      expect(servidor.guardado, 'token-3');
    });

    test('al cerrarse la pantalla principal, ya no escucha las rotaciones', () async {
      await abrir();
      mirando.close();
      await pumpEventQueue();

      push.rotaElToken('token-2');
      await pumpEventQueue();

      expect(servidor.pedidos, ['token-1']);
    });
  });

  group('sin conexión: queda pendiente y se sube al volver', () {
    test('al volver la señal', () async {
      servidor.falla = const TokenPushSinConexionException();
      await abrir();
      expect(servidor.guardado, isNull);

      servidor.falla = null;
      conexion.cambiarA(TipoConexion.sinConexion);
      await pumpEventQueue();
      expect(servidor.guardado, isNull, reason: 'seguir sin señal no reintenta');

      conexion.cambiarA(TipoConexion.datosMoviles);
      await pumpEventQueue();

      expect(servidor.guardado, 'token-1');
    });

    test('al volver a la app', () async {
      servidor.falla = const TokenPushSinConexionException();
      await abrir();

      servidor.falla = null;
      _volverALaApp(binding);
      await pumpEventQueue();

      expect(servidor.guardado, 'token-1');
    });

    test('con el token ya subido, volver a la app o a la señal no lo repite', () async {
      await abrir();

      _volverALaApp(binding);
      conexion.cambiarA(TipoConexion.sinConexion);
      conexion.cambiarA(TipoConexion.wifi);
      await pumpEventQueue();

      expect(servidor.pedidos, ['token-1']);
    });

    test(
      'un sistema que no dio el token (iOS sin registrar) se reintenta al volver a la app',
      () async {
        push.fallaAlObtenerToken = StateError('apns-token-not-set');
        await abrir();
        expect(servidor.pedidos, isEmpty);

        push
          ..fallaAlObtenerToken = null
          ..token = 'token-1';
        _volverALaApp(binding);
        await pumpEventQueue();

        expect(servidor.pedidos, ['token-1']);
      },
    );
  });

  group('al cerrar sesión (el gancho que usa SesionNotifier)', () {
    test('manda el token vacío', () async {
      final c = await abrir();

      await c.read(retiroTokenPushProvider)();

      expect(servidor.pedidos, ['token-1', null]);
      expect(servidor.guardado, isNull);
    });

    test('con el permiso apagado también vacía lo que hubiera de antes', () async {
      sistema.estado = EstadoSistemaNotificaciones.apagadas;
      final c = await abrir();

      await c.read(retiroTokenPushProvider)();

      expect(servidor.pedidos, [null]);
    });

    test('sin conexión no lanza', () async {
      final c = await abrir();
      servidor.falla = const TokenPushSinConexionException();

      await expectLater(c.read(retiroTokenPushProvider)(), completes);
    });
  });
}

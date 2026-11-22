// Cómo están las notificaciones y qué contestó la persona (HU-NOT-001, vista 24): el estado que
// arma `NotificacionesNotifier` con lo que dice el sistema y lo que el teléfono recuerda, y las
// cuatro acciones («Activar», «Ahora no», cerrar el aviso y volver a leer).
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/permiso_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/estado_notificaciones.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

({
  ProviderContainer contenedor,
  PermisoNotificacionesSistemaEnMemoria sistema,
  PermisoNotificacionesRepositoryEnMemoria recuerdo,
})
_armar({
  EstadoSistemaNotificaciones estado = EstadoSistemaNotificaciones.apagadas,
  PedidoNotificaciones? pedido,
  bool avisoCerrado = false,
}) {
  final sistema = PermisoNotificacionesSistemaEnMemoria(estado: estado);
  final recuerdo = PermisoNotificacionesRepositoryEnMemoria(
    pedido: pedido,
    avisoCerrado: avisoCerrado,
  );
  final contenedor = ProviderContainer(
    overrides: [
      permisoNotificacionesSistemaProvider.overrideWithValue(sistema),
      permisoNotificacionesRepositoryProvider.overrideWithValue(recuerdo),
    ],
  );
  addTearDown(contenedor.dispose);
  // Autodispose: se escucha todo el test, como hace la pantalla principal.
  contenedor.listen(notificacionesProvider, (_, _) {});
  return (contenedor: contenedor, sistema: sistema, recuerdo: recuerdo);
}

Future<EstadoNotificaciones> _estado(ProviderContainer c) => c.read(notificacionesProvider.future);

NotificacionesNotifier _accion(ProviderContainer c) => c.read(notificacionesProvider.notifier);

void main() {
  group('el estado al leer', () {
    test(
      'dado que el sistema las tiene activadas, están activadas y no hay nada que pedir',
      () async {
        final t = _armar(estado: EstadoSistemaNotificaciones.activadas);

        final estado = await _estado(t.contenedor);

        expect(estado.permiso, EstadoPermisoNotificaciones.activadas);
        expect(estado.debePedir, isFalse);
        expect(estado.mostrarAviso, isFalse);
      },
    );

    test('activadas sin que se haya pedido: queda anotado que el sistema ya contestó', () async {
      final t = _armar(estado: EstadoSistemaNotificaciones.activadas);

      await _estado(t.contenedor);

      expect(t.recuerdo.pedido, PedidoNotificaciones.sistema);
    });

    test('primer ingreso con las notificaciones apagadas: hay que pedirlas', () async {
      final t = _armar();

      final estado = await _estado(t.contenedor);

      expect(estado.permiso, EstadoPermisoNotificaciones.sinPedir);
      expect(estado.pedidoRespondido, isFalse);
      expect(estado.debePedir, isTrue);
      expect(estado.mostrarAviso, isFalse);
    });

    test('iOS sin preguntar: se puede pedir (sinPedir) aunque quede una marca vieja', () async {
      final t = _armar(
        estado: EstadoSistemaNotificaciones.sinPreguntar,
        pedido: PedidoNotificaciones.sistema,
      );

      final estado = await _estado(t.contenedor);

      expect(estado.permiso, EstadoPermisoNotificaciones.sinPedir);
    });

    test(
      'dijo «Ahora no»: no se vuelve a pedir, el aviso de Hoy lo recuerda y se puede activar',
      () async {
        final t = _armar(pedido: PedidoNotificaciones.ahoraNo);

        final estado = await _estado(t.contenedor);

        expect(estado.permiso, EstadoPermisoNotificaciones.sinPedir);
        expect(estado.debePedir, isFalse);
        expect(estado.mostrarAviso, isTrue);
      },
    );

    test('el sistema ya le preguntó y siguen apagadas: bloqueadas', () async {
      final t = _armar(pedido: PedidoNotificaciones.sistema);

      final estado = await _estado(t.contenedor);

      expect(estado.permiso, EstadoPermisoNotificaciones.bloqueadas);
      expect(estado.debePedir, isFalse);
      expect(estado.mostrarAviso, isTrue);
    });

    test('con el aviso cerrado no vuelve a salir', () async {
      final t = _armar(pedido: PedidoNotificaciones.ahoraNo, avisoCerrado: true);

      final estado = await _estado(t.contenedor);

      expect(estado.mostrarAviso, isFalse);
    });

    test('si el sistema no contesta, el estado queda en error y la app no pide nada', () async {
      final t = _armar();
      t.sistema.fallaAlLeer = true;
      t.contenedor.invalidate(notificacionesProvider);
      t.contenedor.listen(notificacionesProvider, (_, _) {});

      await expectLater(_estado(t.contenedor), throwsA(isA<PermisoNotificacionesException>()));
      expect(t.contenedor.read(notificacionesProvider).value?.debePedir ?? false, isFalse);
    });

    test('si el almacén no se deja leer, tampoco pide nada', () async {
      final t = _armar();
      t.recuerdo.fallaAlLeer = true;
      t.contenedor.invalidate(notificacionesProvider);
      t.contenedor.listen(notificacionesProvider, (_, _) {});

      await expectLater(_estado(t.contenedor), throwsA(anything));
      expect(t.contenedor.read(notificacionesProvider).value?.debePedir ?? false, isFalse);
    });
  });

  group('«Activar»', () {
    test('dado que da el permiso, quedan activadas y anotado que el sistema ya preguntó', () async {
      final t = _armar();
      await _estado(t.contenedor);

      final resultado = await _accion(t.contenedor).activar();

      expect(resultado, ResultadoActivacion.activadas);
      final estado = t.contenedor.read(notificacionesProvider).value!;
      expect(estado.permiso, EstadoPermisoNotificaciones.activadas);
      expect(estado.pedidoRespondido, isTrue);
      expect(estado.debePedir, isFalse);
      expect(t.recuerdo.pedido, PedidoNotificaciones.sistema);
    });

    test('dado que dice «No permitir», quedan bloqueadas y el aviso de Hoy aparece', () async {
      final t = _armar();
      t.sistema.respuestaAlPedir = false;
      await _estado(t.contenedor);

      final resultado = await _accion(t.contenedor).activar();

      expect(resultado, ResultadoActivacion.noConcedido);
      final estado = t.contenedor.read(notificacionesProvider).value!;
      expect(estado.permiso, EstadoPermisoNotificaciones.bloqueadas);
      expect(estado.mostrarAviso, isTrue);
    });

    test('dos toques seguidos comparten el pedido: el diálogo se muestra una sola vez', () async {
      final t = _armar();
      final abierto = t.sistema.dialogoAbierto = Completer<void>();
      await _estado(t.contenedor);

      final primero = _accion(t.contenedor).activar();
      final segundo = _accion(t.contenedor).activar();
      abierto.complete();

      expect(await primero, ResultadoActivacion.activadas);
      expect(await segundo, ResultadoActivacion.activadas);
      expect(t.sistema.pedidos, 1);
    });

    test(
      'si la plataforma falla a mitad, devuelve fallo, no anota nada y se puede reintentar',
      () async {
        final t = _armar();
        t.sistema.fallaAlPedir = true;
        await _estado(t.contenedor);

        expect(await _accion(t.contenedor).activar(), ResultadoActivacion.fallo);
        expect(t.recuerdo.pedido, isNull);
        expect(t.contenedor.read(notificacionesProvider).value!.debePedir, isTrue);

        t.sistema.fallaAlPedir = false;
        expect(await _accion(t.contenedor).activar(), ResultadoActivacion.activadas);
      },
    );

    test(
      'si no se pudo guardar lo contestado, igual quedan activadas (de mejor esfuerzo)',
      () async {
        final t = _armar();
        t.recuerdo.fallaAlAnotar = true;
        await _estado(t.contenedor);

        expect(await _accion(t.contenedor).activar(), ResultadoActivacion.activadas);
        expect(t.contenedor.read(notificacionesProvider).value!.activadas, isTrue);
      },
    );

    test('sin estado leído todavía devuelve fallo y no abre el diálogo', () async {
      final t = _armar();
      t.sistema.lecturaDemorada = Completer<void>();
      t.contenedor.invalidate(notificacionesProvider);
      t.contenedor.listen(notificacionesProvider, (_, _) {});

      expect(await _accion(t.contenedor).activar(), ResultadoActivacion.fallo);
      expect(t.sistema.pedidos, 0);
    });
  });

  group('«Ahora no»', () {
    test('anota la respuesta: no se vuelve a pedir y las notificaciones siguen apagadas', () async {
      final t = _armar();
      await _estado(t.contenedor);

      await _accion(t.contenedor).ahoraNo();

      final estado = t.contenedor.read(notificacionesProvider).value!;
      expect(estado.debePedir, isFalse);
      expect(estado.mostrarAviso, isTrue);
      expect(t.recuerdo.pedido, PedidoNotificaciones.ahoraNo);
      expect(t.sistema.pedidos, 0);
    });

    test('dos veces seguidas es lo mismo que una', () async {
      final t = _armar();
      await _estado(t.contenedor);

      await Future.wait([_accion(t.contenedor).ahoraNo(), _accion(t.contenedor).ahoraNo()]);

      expect(t.recuerdo.pedido, PedidoNotificaciones.ahoraNo);
      expect(t.contenedor.read(notificacionesProvider).value!.debePedir, isFalse);
    });

    test('si no se pudo guardar, igual deja de pedir mientras la app siga abierta', () async {
      final t = _armar();
      t.recuerdo.fallaAlAnotar = true;
      await _estado(t.contenedor);

      await _accion(t.contenedor).ahoraNo();

      expect(t.contenedor.read(notificacionesProvider).value!.debePedir, isFalse);
    });
  });

  group('el aviso de Hoy', () {
    test('cerrarlo lo saca y queda anotado', () async {
      final t = _armar(pedido: PedidoNotificaciones.ahoraNo);
      await _estado(t.contenedor);

      await _accion(t.contenedor).cerrarAviso();

      expect(t.contenedor.read(notificacionesProvider).value!.mostrarAviso, isFalse);
      expect(t.recuerdo.avisoCerrado, isTrue);
    });
  });

  group('volver a leer', () {
    test('si las activó en los ajustes del teléfono, pasan a activadas y el aviso se va', () async {
      final t = _armar(pedido: PedidoNotificaciones.sistema);
      await _estado(t.contenedor);
      expect(t.contenedor.read(notificacionesProvider).value!.mostrarAviso, isTrue);

      t.sistema.estado = EstadoSistemaNotificaciones.activadas;
      await _accion(t.contenedor).refrescar();

      final estado = t.contenedor.read(notificacionesProvider).value!;
      expect(estado.activadas, isTrue);
      expect(estado.mostrarAviso, isFalse);
    });

    test('si las apagó en los ajustes, quedan bloqueadas', () async {
      final t = _armar(estado: EstadoSistemaNotificaciones.activadas);
      await _estado(t.contenedor);

      t.sistema.estado = EstadoSistemaNotificaciones.apagadas;
      await _accion(t.contenedor).refrescar();

      expect(
        t.contenedor.read(notificacionesProvider).value!.permiso,
        EstadoPermisoNotificaciones.bloqueadas,
      );
    });

    test('si no se puede leer, deja lo que había', () async {
      final t = _armar(pedido: PedidoNotificaciones.ahoraNo);
      final antes = await _estado(t.contenedor);

      t.sistema.fallaAlLeer = true;
      await _accion(t.contenedor).refrescar();

      expect(t.contenedor.read(notificacionesProvider).value, antes);
    });

    test('una lectura que llega tarde no pisa lo que la persona acaba de hacer', () async {
      final t = _armar();
      await _estado(t.contenedor);
      // La lectura de «volver a la app» sale con el sistema apagado y se queda esperando…
      final demora = t.sistema.lecturaDemorada = Completer<void>();
      final lectura = _accion(t.contenedor).refrescar();
      await Future<void>.delayed(Duration.zero);
      t.sistema.lecturaDemorada = null;

      // …y mientras tanto la persona toca «Ahora no».
      await _accion(t.contenedor).ahoraNo();
      demora.complete();
      await lectura;

      expect(t.contenedor.read(notificacionesProvider).value!.pedidoRespondido, isTrue);
    });

    test('con el diálogo del sistema abierto no se vuelve a leer', () async {
      final t = _armar();
      await _estado(t.contenedor);
      final abierto = t.sistema.dialogoAbierto = Completer<void>();
      final activando = _accion(t.contenedor).activar();
      await Future<void>.delayed(Duration.zero);
      final lecturas = t.sistema.lecturas;

      await _accion(t.contenedor).refrescar();

      expect(t.sistema.lecturas, lecturas);
      abierto.complete();
      await activando;
    });
  });

  group('abrir los ajustes del teléfono', () {
    test('devuelve si pudo abrirlos', () async {
      final t = _armar(pedido: PedidoNotificaciones.sistema);
      await _estado(t.contenedor);

      expect(await _accion(t.contenedor).abrirAjustes(), isTrue);
      expect(t.sistema.ajustesAbiertos, 1);

      t.sistema.puedeAbrirAjustes = false;
      expect(await _accion(t.contenedor).abrirAjustes(), isFalse);
    });
  });
}

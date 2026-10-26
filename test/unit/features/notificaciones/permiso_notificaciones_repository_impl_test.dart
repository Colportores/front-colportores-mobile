// Lo que el teléfono recuerda del permiso de notificaciones (HU-NOT-001): sobre el almacén seguro,
// con las claves `permisoNotificaciones` y `avisoNotificacionesCerrado`.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/permiso_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

void main() {
  late AlmacenSeguroEnMemoria almacen;
  late PermisoNotificacionesRepositoryImpl repositorio;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    repositorio = PermisoNotificacionesRepositoryImpl(almacen, logger: loggerMudo());
  });

  test('las claves tienen su nombre en el dispositivo', () {
    expect(ClaveSegura.permisoNotificaciones.id, 'notifications_permission');
    expect(ClaveSegura.avisoNotificacionesCerrado.id, 'notifications_banner_closed');
  });

  group('el pedido', () {
    test('dado que nunca se le pidió nada, no hay pedido', () async {
      expect(await repositorio.leerPedido(), isNull);
    });

    test('«Ahora no» queda guardado como ahora_no', () async {
      await repositorio.anotarPedido(PedidoNotificaciones.ahoraNo);

      expect(almacen.contenido[ClaveSegura.permisoNotificaciones], 'ahora_no');
      expect(await repositorio.leerPedido(), PedidoNotificaciones.ahoraNo);
    });

    test('el diálogo del sistema queda guardado como sistema', () async {
      await repositorio.anotarPedido(PedidoNotificaciones.sistema);

      expect(almacen.contenido[ClaveSegura.permisoNotificaciones], 'sistema');
      expect(await repositorio.leerPedido(), PedidoNotificaciones.sistema);
    });

    test('«sistema» pisa a «Ahora no» (lo pidió después desde Configuración)', () async {
      await repositorio.anotarPedido(PedidoNotificaciones.ahoraNo);
      await repositorio.anotarPedido(PedidoNotificaciones.sistema);

      expect(await repositorio.leerPedido(), PedidoNotificaciones.sistema);
    });

    test('«Ahora no» nunca pisa a «sistema»: después del diálogo no se desanota', () async {
      await repositorio.anotarPedido(PedidoNotificaciones.sistema);
      await repositorio.anotarPedido(PedidoNotificaciones.ahoraNo);

      expect(await repositorio.leerPedido(), PedidoNotificaciones.sistema);
    });

    test('un valor que no se reconoce cuenta como «nunca se pidió»', () async {
      await almacen.escribir(ClaveSegura.permisoNotificaciones, 'basura');

      expect(await repositorio.leerPedido(), isNull);
    });

    test('anotar con el almacén roto no lanza: queda en el log', () async {
      final roto = PermisoNotificacionesRepositoryImpl(
        AlmacenSeguroEnMemoria()..simularFalla = true,
        logger: loggerMudo(),
      );

      await roto.anotarPedido(PedidoNotificaciones.sistema);
      await roto.anotarAvisoCerrado();
    });

    test('leer con el almacén roto lanza (la app entonces no pide nada)', () async {
      final roto = PermisoNotificacionesRepositoryImpl(
        AlmacenSeguroEnMemoria()..simularFalla = true,
        logger: loggerMudo(),
      );

      expect(roto.leerPedido(), throwsA(isA<AlmacenSeguroException>()));
    });

    test('dos anotaciones seguidas, sin esperar, quedan en el orden en que se pidieron', () async {
      final primera = repositorio.anotarPedido(PedidoNotificaciones.ahoraNo);
      final segunda = repositorio.anotarPedido(PedidoNotificaciones.sistema);
      final lectura = repositorio.leerPedido();

      await Future.wait([primera, segunda]);

      expect(await lectura, PedidoNotificaciones.sistema);
    });
  });

  group('el aviso de Hoy', () {
    test('dado que no lo cerró, se muestra', () async {
      expect(await repositorio.leerAvisoCerrado(), isFalse);
    });

    test('cerrado queda guardado y no vuelve', () async {
      await repositorio.anotarAvisoCerrado();

      expect(almacen.contenido[ClaveSegura.avisoNotificacionesCerrado], '1');
      expect(await repositorio.leerAvisoCerrado(), isTrue);
    });

    test('cerrar dos veces es lo mismo que una', () async {
      await repositorio.anotarAvisoCerrado();
      await repositorio.anotarAvisoCerrado();

      expect(await repositorio.leerAvisoCerrado(), isTrue);
    });
  });
}

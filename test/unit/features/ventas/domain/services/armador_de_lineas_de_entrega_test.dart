// «Qué entregás» (27B·01, HU-VEN-002): de los ítems de la venta a las filas que se tildan.
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/productos_de_la_entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
import 'package:colportores_mobile/features/ventas/domain/services/armador_de_lineas_de_entrega.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/entrega_falsos.dart';
import '../../../../../helpers/venta_falsos.dart';

void main() {
  group('producto suelto', () {
    test('es una fila «Nombre × cantidad» con la cantidad de la línea', () {
      final lineas = ArmadorDeLineasDeEntrega.armar([
        itemDe('i-1', 'v-1', productoId: 'p-nuestra-salud', cantidad: 3),
      ], productosDeEntrega);

      final linea = lineas.single;
      expect(linea.titulo, 'Nuestra Salud × 3');
      expect(linea.nombre, 'Nuestra Salud');
      expect(linea.detalle, isNull);
      expect(linea.productos, [
        const ComponenteVendido(productoId: 'p-nuestra-salud', cantidad: 3),
      ]);
    });

    test('un producto que el catálogo no conoce no desaparece: va como «Producto sin nombre»', () {
      final lineas = ArmadorDeLineasDeEntrega.armar([
        itemDe('i-1', 'v-1', productoId: 'p-raro', cantidad: 1),
      ], const ProductosDeLaEntrega());

      expect(lineas.single.titulo, 'Producto sin nombre × 1');
      expect(lineas.single.productos.single.productoId, 'p-raro');
    });

    test('cada ítem tiene su fila, en el orden de la venta, con claves distintas', () {
      final lineas = ArmadorDeLineasDeEntrega.armar([
        itemDe('i-1', 'v-1', productoId: 'p-nuestra-salud', cantidad: 1),
        itemDe('i-2', 'v-1', productoId: 'p-vida-feliz', cantidad: 2),
      ], productosDeEntrega);

      expect(lineas.map((l) => l.titulo), ['Nuestra Salud × 1', 'Vida Feliz × 2']);
      expect(lineas.map((l) => l.clave).toSet(), hasLength(2));
    });
  });

  group('combo', () {
    VentaItem combo({int cantidad = 1}) => itemDe(
      'i-1',
      'v-1',
      productoId: null,
      coleccionId: 'k-2',
      cantidad: cantidad,
      precio: 890000,
      componentes: const [
        ComponenteVendido(productoId: 'p-camino'),
        ComponenteVendido(productoId: 'p-vida-feliz'),
        ComponenteVendido(productoId: 'p-deseado'),
        ComponenteVendido(productoId: 'p-salud'),
        ComponenteVendido(productoId: 'p-hijos'),
      ],
    );

    test('abre un libro por fila y junta la base en una sola', () {
      final lineas = ArmadorDeLineasDeEntrega.armar([combo()], productosDeEntrega);

      expect(lineas.map((l) => l.titulo), [
        'Salud y Hogar × 1',
        'Nuestros Hijos × 1',
        'El camino a Cristo, Vida Feliz y El Deseado de todas las gentes',
      ]);
      final base = lineas.last;
      expect(base.detalle, 'Base de la colección');
      expect(base.productos.map((p) => p.productoId), ['p-camino', 'p-vida-feliz', 'p-deseado']);
    });

    test('con dos colecciones iguales, las cantidades se multiplican', () {
      final lineas = ArmadorDeLineasDeEntrega.armar([combo(cantidad: 2)], productosDeEntrega);

      expect(lineas.first.titulo, 'Salud y Hogar × 2');
      expect(lineas.last.productos.every((p) => p.cantidad == 2), isTrue);
    });

    test('sin base conocida cada componente tiene su fila: no se esconde nada', () {
      final lineas = ArmadorDeLineasDeEntrega.armar([
        combo(),
      ], const ProductosDeLaEntrega(nombres: {'p-camino': 'El camino a Cristo'}));

      expect(lineas, hasLength(5));
      expect(lineas.first.titulo, 'El camino a Cristo × 1');
      expect(lineas.every((l) => l.detalle == null), isTrue);
    });

    test('las claves de las filas de un combo son distintas entre sí y entre ítems', () {
      final lineas = ArmadorDeLineasDeEntrega.armar([
        combo(),
        itemDe('i-9', 'v-1', productoId: 'p-nuestra-salud', cantidad: 1),
      ], productosDeEntrega);

      expect(lineas.map((l) => l.clave).toSet(), hasLength(lineas.length));
    });
  });

  test('un ítem dado de baja no se ofrece para entregar', () {
    final borrado = VentaItem(
      id: 'i-1',
      ventaId: 'v-1',
      productoId: 'p-vida-feliz',
      cantidad: 1,
      precioUnitarioCentavos: 1000,
      subtotalCentavos: 1000,
      auditoria: auditoriaDe(borrada: t0),
    );

    expect(ArmadorDeLineasDeEntrega.armar([borrado], productosDeEntrega), isEmpty);
  });

  test('sin ítems no hay filas', () {
    expect(ArmadorDeLineasDeEntrega.armar(const [], productosDeEntrega), isEmpty);
  });
}

// Test de dominio: Dart puro. Cuánto hay que entregar de una venta (HU-VEN-002, #430).
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/services/reglas_de_entrega.dart';
import 'package:test/test.dart';

RenglonVendido _suelto(String producto, int cantidad) =>
    (productoId: producto, cantidad: cantidad, componentes: null);

RenglonVendido _combo(int unidades, List<(String, int)> componentes) => (
  productoId: null,
  cantidad: unidades,
  componentes: [for (final (id, n) in componentes) ComponenteVendido(productoId: id, cantidad: n)],
);

void main() {
  group('cantidadesVendidas', () {
    test('dado 3 libros de un producto, cuando se cuenta, es una cantidad de 3', () {
      expect(ReglasDeEntrega.cantidadesVendidas([_suelto('a', 3)]), {'a': 3});
    });

    test('dado el mismo producto en dos renglones, cuando se cuenta, es una sola cantidad', () {
      expect(ReglasDeEntrega.cantidadesVendidas([_suelto('a', 1), _suelto('a', 2)]), {'a': 3});
    });

    test('dado un combo de 2 unidades, cuando se cuenta, cada componente va por su cantidad y las '
        'unidades', () {
      final vendido = ReglasDeEntrega.cantidadesVendidas([
        _combo(2, [('a', 1), ('b', 2)]),
      ]);

      expect(vendido, {'a': 2, 'b': 4});
    });

    test('dado un producto suelto y el mismo dentro de un combo, cuando se cuenta, se suman', () {
      final vendido = ReglasDeEntrega.cantidadesVendidas([
        _suelto('a', 1),
        _combo(3, [('a', 1), ('b', 1)]),
      ]);

      expect(vendido, {'a': 4, 'b': 3});
    });

    test('dado un combo sin componentes, cuando se cuenta, no aporta nada', () {
      expect(ReglasDeEntrega.cantidadesVendidas([_combo(2, const [])]), isEmpty);
    });

    test('dado un renglón sin producto ni componentes o con cantidad cero, cuando se cuenta, se '
        'ignora', () {
      final vendido = ReglasDeEntrega.cantidadesVendidas([
        (productoId: null, cantidad: 2, componentes: null),
        _suelto('a', 0),
        _suelto('b', 1),
      ]);

      expect(vendido, {'b': 1});
    });

    test('dado varios productos, cuando se cuenta, conserva el orden en que aparecen', () {
      final vendido = ReglasDeEntrega.cantidadesVendidas([
        _suelto('z', 1),
        _suelto('a', 1),
        _suelto('z', 1),
      ]);

      expect(vendido.keys, ['z', 'a']);
    });
  });

  group('cantidadesFaltantes', () {
    test('dado lo entregado a medias, cuando se mide, falta la resta', () {
      expect(ReglasDeEntrega.cantidadesFaltantes({'a': 3, 'b': 2}, {'a': 1}), {'a': 2, 'b': 2});
    });

    test('dado todo entregado, cuando se mide, no falta nada', () {
      expect(ReglasDeEntrega.cantidadesFaltantes({'a': 3}, {'a': 3}), isEmpty);
    });

    test('dado un producto entregado de más, cuando se mide, no le resta a otro', () {
      expect(ReglasDeEntrega.cantidadesFaltantes({'a': 3, 'b': 2}, {'a': 9}), {'b': 2});
    });

    test('dado un producto entregado que no se vendió, cuando se mide, no aparece', () {
      expect(ReglasDeEntrega.cantidadesFaltantes({'a': 1}, {'x': 5}), {'a': 1});
    });
  });

  group('estaEntregada', () {
    test('dado todo entregado, cuando se pregunta, es que sí', () {
      expect(ReglasDeEntrega.estaEntregada({'a': 3, 'b': 1}, {'a': 3, 'b': 1}), isTrue);
    });

    test('dado que falta un producto, cuando se pregunta, es que no', () {
      expect(ReglasDeEntrega.estaEntregada({'a': 3, 'b': 1}, {'a': 3}), isFalse);
    });

    test('dado que falta una unidad, cuando se pregunta, es que no', () {
      expect(ReglasDeEntrega.estaEntregada({'a': 3}, {'a': 2}), isFalse);
    });

    test('dado que no se vendió nada, cuando se pregunta, no está «entregada»', () {
      expect(ReglasDeEntrega.estaEntregada({}, {}), isFalse);
      expect(ReglasDeEntrega.estaEntregada({}, {'a': 1}), isFalse);
    });
  });
}

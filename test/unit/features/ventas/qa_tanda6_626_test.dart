// QA de la tanda 6 de #537 (#626, PR #731): bordes de lo que el PR cambió en la lógica de ventas.
// No repite los casos del PR; cubre el límite justo (99.999 entra, 100.000 no), productos distintos
// que no se suman entre sí, y que el espacio sin quiebre de los montos no cambia el texto visible.
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/linea_de_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/registrar_venta_use_case.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:test/test.dart';

void main() {
  const max = RegistrarVentaUseCase.maximoPorLinea;

  group('QA #430: tope de unidades por producto en problemaDeLasLineas', () {
    test(
      'justo en el máximo entra: una línea suelta, un combo de 1 y un combo con el producto fijo',
      () {
        const suelta = LineaDeProducto(productoId: 'p', cantidad: max, precioCentavos: 100);
        const combo = LineaDeCombo(
          comboId: 'c',
          componentes: [ComponenteVendido(productoId: 'p', cantidad: max)],
          cantidad: 1,
          precioCentavos: 100,
        );
        expect(RegistrarVentaUseCase.problemaDeLasLineas([suelta]), isNull);
        expect(RegistrarVentaUseCase.problemaDeLasLineas([combo]), isNull);
      },
    );

    test('un producto repartido en dos líneas sueltas que pasan del máximo se rechaza', () {
      const a = LineaDeProducto(productoId: 'p', cantidad: max, precioCentavos: 0);
      const b = LineaDeProducto(productoId: 'p', cantidad: 1, precioCentavos: 0);
      expect(
        RegistrarVentaUseCase.problemaDeLasLineas([a, b]),
        'Revisá las cantidades de la venta',
      );
    });

    test('productos distintos al máximo cada uno no se suman entre sí', () {
      const a = LineaDeProducto(productoId: 'p', cantidad: max, precioCentavos: 0);
      const b = LineaDeProducto(productoId: 'q', cantidad: max, precioCentavos: 0);
      const combo = LineaDeCombo(
        comboId: 'c',
        componentes: [ComponenteVendido(productoId: 'r', cantidad: max)],
        cantidad: 1,
        precioCentavos: 0,
      );
      expect(RegistrarVentaUseCase.problemaDeLasLineas([a, b, combo]), isNull);
    });

    test('dos componentes del mismo producto dentro de un combo se suman', () {
      const combo = LineaDeCombo(
        comboId: 'c',
        componentes: [
          ComponenteVendido(productoId: 'p', cantidad: 50000),
          ComponenteVendido(productoId: 'p', cantidad: 50000),
        ],
        cantidad: 1,
        precioCentavos: 0,
      );
      expect(
        RegistrarVentaUseCase.problemaDeLasLineas([combo]),
        'Revisá las cantidades de la venta',
      );
    });

    test(
      'una línea ya inválida sigue dando el mismo aviso (cantidad 0) y la lista vacía el suyo',
      () {
        const cero = LineaDeProducto(productoId: 'p', cantidad: 0, precioCentavos: 0);
        expect(
          RegistrarVentaUseCase.problemaDeLasLineas([cero]),
          'Revisá las cantidades de la venta',
        );
        expect(
          RegistrarVentaUseCase.problemaDeLasLineas(const []),
          'Agregá al menos un producto a la venta',
        );
      },
    );
  });

  group('QA #161: montoSinQuiebre', () {
    const valores = [0, 1, 50, 99, 100, 450000, 890050, 2147483647];

    test('el texto visible es el mismo que el de monto, salvo el espacio sin quiebre', () {
      for (final v in valores) {
        expect(
          FormatoVenta.montoSinQuiebre(v).replaceAll(' ', ' '),
          FormatoVenta.monto(v),
          reason: 'monto $v',
        );
      }
    });

    test('nunca queda un espacio común entre «\$» y el número (el quiebre de línea)', () {
      for (final v in valores) {
        final t = FormatoVenta.montoSinQuiebre(v);
        expect(t, startsWith('\$ '), reason: 'monto $v');
        expect(t.contains('\$ '), isFalse, reason: 'monto $v');
      }
    });

    test('el monto sin quiebre sigue leyéndose como monto al volver a parsearlo', () {
      expect(FormatoVenta.parsearMonto(FormatoVenta.montoSinQuiebre(850000)), 850000);
    });
  });
}

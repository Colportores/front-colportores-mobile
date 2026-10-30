// Igualdad y valores de las entidades de la devolución (HU-VEN-004, #161): dos con los mismos datos
// son iguales, y cambiar cualquier dato las hace distintas. De esto depende que la pantalla no
// redibuje de más y que los streams con `distinct()` no repitan el mismo saldo.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_para_devolver.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/registrar_devolucion_use_case.dart';
import 'package:test/test.dart';

final _t = DateTime.utc(2026, 10, 14, 12);

RenglonDeLaVenta _renglon({
  String id = 'i-1',
  String titulo = 'Salud y Hogar',
  int cantidad = 2,
  int precio = 260000,
  int devueltas = 0,
  List<ComponenteVendido>? componentes,
}) => RenglonDeLaVenta(
  ventaItemId: id,
  titulo: titulo,
  productoId: componentes == null ? 'p-1' : null,
  componentes: componentes,
  cantidad: cantidad,
  precioUnitarioCentavos: precio,
  unidadesDevueltas: devueltas,
);

VentaParaDevolver _venta({int cobrado = 520000, List<RenglonDeLaVenta>? renglones}) =>
    VentaParaDevolver(
      ventaId: 'v-1',
      numeroTalonario: '0042',
      fecha: _t,
      montoTotalCentavos: 520000,
      cobradoCentavos: cobrado,
      renglones: renglones ?? [_renglon()],
    );

Devolucion _devolucion({String id = 'd-1', int retenido = 0, int? reembolsado, String? motivo}) =>
    Devolucion(
      id: id,
      ventaId: 'v-1',
      productos: const [ProductoDevuelto(productoId: 'p-1', ventaItemId: 'i-1', cantidad: 1)],
      dineroRetenidoCentavos: retenido,
      montoReembolsadoCentavos: reembolsado,
      motivo: motivo,
      fechaDevolucion: _t,
      auditoria: Auditoria(createdAt: _t, updatedAt: _t, createdBy: 'col-1'),
    );

void main() {
  group('RenglonDeLaVenta', () {
    test('dos renglones con los mismos datos son iguales y cualquier dato distinto los separa', () {
      expect(_renglon(), _renglon());
      expect(_renglon().hashCode, _renglon().hashCode);
      for (final otro in [
        _renglon(id: 'i-2'),
        _renglon(titulo: 'Otro'),
        _renglon(cantidad: 3),
        _renglon(precio: 1),
        _renglon(devueltas: 1),
        _renglon(componentes: const [ComponenteVendido(productoId: 'p-a')]),
      ]) {
        expect(otro, isNot(_renglon()));
      }
    });

    test('lo que queda por devolver y lo que valen las unidades devueltas', () {
      final r = _renglon(devueltas: 1);

      expect(r.disponibles, 1);
      expect(r.valorDevueltoCentavos, 260000);
      expect(r.esCombo, isFalse);
      expect(_renglon(devueltas: 5).disponibles, 0);
      expect(_renglon(devueltas: 5).valorDevueltoCentavos, 520000);
      expect(_renglon(componentes: const [ComponenteVendido(productoId: 'p-a')]).esCombo, isTrue);
    });
  });

  group('CuentaDeLaVenta', () {
    test('igualdad por todos sus datos', () {
      const base = CuentaDeLaVenta(montoTotalCentavos: 100, cobradoCentavos: 50);

      expect(base, const CuentaDeLaVenta(montoTotalCentavos: 100, cobradoCentavos: 50));
      for (final otra in const [
        CuentaDeLaVenta(montoTotalCentavos: 101, cobradoCentavos: 50),
        CuentaDeLaVenta(montoTotalCentavos: 100, cobradoCentavos: 51),
        CuentaDeLaVenta(montoTotalCentavos: 100, cobradoCentavos: 50, devueltoCentavos: 1),
        CuentaDeLaVenta(montoTotalCentavos: 100, cobradoCentavos: 50, reembolsadoCentavos: 1),
        CuentaDeLaVenta(montoTotalCentavos: 100, cobradoCentavos: 50, retenidoCentavos: 1),
      ]) {
        expect(otra, isNot(base));
      }
    });
  });

  group('VentaParaDevolver', () {
    test('igualdad por todos sus datos', () {
      expect(_venta(), _venta());
      expect(_venta(cobrado: 1), isNot(_venta()));
      expect(_venta(renglones: [_renglon(devueltas: 1)]), isNot(_venta()));
    });

    test('lo que queda por devolver y si ya volvió todo', () {
      expect(_venta().unidadesDisponibles, 2);
      expect(_venta().estaTodoDevuelto, isFalse);
      final entera = _venta(renglones: [_renglon(devueltas: 2)]);
      expect(entera.unidadesDisponibles, 0);
      expect(entera.estaTodoDevuelto, isTrue);
      expect(entera.devueltoCentavos, 520000);
      expect(entera.seQuedaConCentavos, 0);
    });
  });

  group('CuentaDeLaDevolucion', () {
    const base = CuentaDeLaDevolucion(
      unidades: 1,
      valorCentavos: 100,
      seQuedaConCentavos: 50,
      yaPagoCentavos: 70,
      pagoDeMasCentavos: 20,
      saldoNuevoCentavos: 0,
      esTotal: false,
    );

    test('igualdad por todos sus datos', () {
      expect(
        base,
        const CuentaDeLaDevolucion(
          unidades: 1,
          valorCentavos: 100,
          seQuedaConCentavos: 50,
          yaPagoCentavos: 70,
          pagoDeMasCentavos: 20,
          saldoNuevoCentavos: 0,
          esTotal: false,
        ),
      );
      expect(
        base,
        isNot(
          const CuentaDeLaDevolucion(
            unidades: 1,
            valorCentavos: 100,
            seQuedaConCentavos: 50,
            yaPagoCentavos: 70,
            pagoDeMasCentavos: 20,
            saldoNuevoCentavos: 0,
            esTotal: true,
          ),
        ),
      );
    });

    test('hay que elegir solo si pagó de más y está vacía solo sin unidades', () {
      expect(base.hayQueElegir, isTrue);
      expect(base.estaVacia, isFalse);
      const vacia = CuentaDeLaDevolucion(
        unidades: 0,
        valorCentavos: 0,
        seQuedaConCentavos: 50,
        yaPagoCentavos: 0,
        pagoDeMasCentavos: 0,
        saldoNuevoCentavos: 50,
        esTotal: false,
      );
      expect(vacia.hayQueElegir, isFalse);
      expect(vacia.estaVacia, isTrue);
    });
  });

  group('Devolucion y ProductoDevuelto', () {
    test('igualdad por todos sus datos', () {
      expect(_devolucion(), _devolucion());
      for (final otra in [
        _devolucion(id: 'd-2'),
        _devolucion(retenido: 1),
        _devolucion(reembolsado: 1),
        _devolucion(motivo: 'x'),
      ]) {
        expect(otra, isNot(_devolucion()));
      }
      expect(
        const ProductoDevuelto(productoId: 'p', ventaItemId: 'i', cantidad: 1),
        isNot(const ProductoDevuelto(productoId: 'p', ventaItemId: 'i', cantidad: 2)),
      );
    });

    test('su lista de productos no se puede cambiar por fuera', () {
      expect(
        () => _devolucion().productos.add(
          const ProductoDevuelto(productoId: 'p', ventaItemId: 'i', cantidad: 1),
        ),
        throwsUnsupportedError,
      );
      expect(_devolucion().estaBorrada, isFalse);
    });
  });

  group('PedidoDeDevolucion y DevolucionRegistrada', () {
    PedidoDeDevolucion pedido({String id = 'd-1', QueHacerConLaDiferencia? queHacer}) =>
        PedidoDeDevolucion(
          id: id,
          ventaId: 'v-1',
          colportorId: 'col-1',
          unidadesPorRenglon: const {'i-1': 1},
          queHacer: queHacer,
          ahora: _t,
        );

    test('el pedido es igual con los mismos datos', () {
      expect(pedido(), pedido());
      expect(pedido(id: 'd-2'), isNot(pedido()));
      expect(pedido(queHacer: QueHacerConLaDiferencia.retener), isNot(pedido()));
    });

    DevolucionRegistrada registrada({int saldo = 0, bool yaEstaba = false}) => DevolucionRegistrada(
      devolucion: _devolucion(),
      totalCentavos: 100,
      saldoCentavos: saldo,
      deboAlClienteCentavos: 0,
      eraTotal: false,
      yaEstaba: yaEstaba,
    );

    test('lo registrado es igual con los mismos datos', () {
      expect(registrada(), registrada());
      expect(registrada(saldo: 1), isNot(registrada()));
      expect(registrada(yaEstaba: true), isNot(registrada()));
    });
  });

  group('RegistrarDevolucionParams', () {
    RegistrarDevolucionParams params({String motivo = 'a', int unidades = 1}) =>
        RegistrarDevolucionParams(
          devolucionId: 'd-1',
          ventaId: 'v-1',
          colportorId: 'col-1',
          unidadesPorRenglon: {'i-1': unidades},
          queHacer: QueHacerConLaDiferencia.retener,
          motivo: motivo,
        );

    test('igualdad por todos sus datos', () {
      expect(params(), params());
      expect(params(motivo: 'b'), isNot(params()));
      expect(params(unidades: 2), isNot(params()));
    });
  });
}

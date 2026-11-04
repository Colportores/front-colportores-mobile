// Qué sigue de «$ Cobrar» según las ventas con saldo (vista 39, C·08, #440).
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/value_objects/paso_que_venta.dart';
import 'package:test/test.dart';

VentaConSaldo _venta(String id, {int total = 120000, int cobrado = 0}) => VentaConSaldo(
  ventaId: id,
  numeroTalonario: id,
  fecha: DateTime.utc(2026, 10, 12, 15),
  montoTotalCentavos: total,
  cobradoCentavos: cobrado,
);

void main() {
  group('PasoQueVenta.de', () {
    test('sin ventas, no hay nada para cobrar', () {
      expect(PasoQueVenta.de(const []), const SinVentasConSaldo());
    });

    test('con una sola venta con saldo, el paso de elegir se salta', () {
      final v = _venta('v-1');

      expect(PasoQueVenta.de([v]), UnaVentaConSaldo(v));
    });

    test('con varias, se ofrecen todas en el orden en que llegan', () {
      final ventas = [_venta('v-1'), _venta('v-2'), _venta('v-3')];

      final paso = PasoQueVenta.de(ventas);

      expect(paso, isA<VariasVentasConSaldo>());
      expect((paso as VariasVentasConSaldo).ventas, ventas);
    });

    test('una venta ya pagada no cuenta: con una sola que debe, se salta', () {
      final debe = _venta('v-1');
      final pagada = _venta('v-2', cobrado: 120000);

      expect(PasoQueVenta.de([pagada, debe]), UnaVentaConSaldo(debe));
    });

    test('si todas están pagadas, no hay nada para cobrar', () {
      expect(
        PasoQueVenta.de([_venta('v-1', cobrado: 120000), _venta('v-2', cobrado: 200000)]),
        const SinVentasConSaldo(),
      );
    });

    test('un cobro de más (saldo negativo) tampoco cuenta como saldo', () {
      expect(PasoQueVenta.de([_venta('v-1', cobrado: 130000)]), const SinVentasConSaldo());
    });
  });
}

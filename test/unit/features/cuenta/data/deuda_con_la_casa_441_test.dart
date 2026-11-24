// HU-CTA-002 (#441, #671) — la entidad de la deuda con la casa editora: qué dice cada caso. La cuenta se
// hace en el teléfono con lo que baja con la sincronización: ver `calculador_de_la_deuda_test.dart` y
// `deuda_desde_la_sincronizacion_671_test.dart`.
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('La entidad: qué dice cada caso', () {
    DeudaConLaCasa con({int total = 0, int suma = 0, int pedidos = 0}) => DeudaConLaCasa(
      deudaTotalCentavos: total,
      sumaDeSaldosCentavos: suma,
      depositosValidadosCentavos: 0,
      pedidos: [
        for (var i = 0; i < pedidos; i++)
          PedidoConSaldo(
            pedidoId: 'p-$i',
            fechaPedido: DateTime.utc(2026, 10, 1),
            montoCentavos: 100,
            pagadoCentavos: 0,
            saldoCentavos: 100,
            lineas: const [],
          ),
      ],
    );

    test(
      'la variación es la deuda de hoy menos la de hace 7 días, y sin la de hace 7 días no hay',
      () {
        DeudaConLaCasa de({int? hace7}) => DeudaConLaCasa(
          deudaTotalCentavos: 1840000,
          sumaDeSaldosCentavos: 1840000,
          depositosValidadosCentavos: 0,
          pedidos: const [],
          deudaHace7DiasCentavos: hace7,
        );

        expect(de(hace7: 2050000).variacionCentavos, -210000);
        expect(de(hace7: 1500000).variacionCentavos, 340000);
        expect(de(hace7: 1840000).variacionCentavos, 0);
        expect(de().variacionCentavos, isNull);
        // La deuda de hace 7 días cuenta en la igualdad.
        expect(de(hace7: 1), isNot(equals(de(hace7: 2))));
        expect(de(hace7: 1), equals(de(hace7: 1)));
      },
    );

    test('sin deuda: cero y ningún pedido', () {
      expect(con().sinDeuda, isTrue);
      expect(con().saldosNoDanElTotal, isFalse);
      expect(con(total: 100, pedidos: 1, suma: 100).sinDeuda, isFalse);
    });

    test('con deuda real y ningún pedido que la explique, no es «sin deuda» y se aclara', () {
      final d = con(total: 500);
      expect(d.sinDeuda, isFalse);
      expect(d.saldosNoDanElTotal, isTrue);
    });

    test('en cero pero con pedidos con saldo, no es «sin deuda» y se aclara', () {
      final d = con(suma: 100, pedidos: 1);
      expect(d.sinDeuda, isFalse);
      expect(d.saldosNoDanElTotal, isTrue);
    });

    test('quedar a favor sin saldos ya se explica solo; con saldos que no cuadran, se aclara', () {
      expect(con(total: -500).aFavor, isTrue);
      expect(con(total: -500).saldosNoDanElTotal, isFalse);
      expect(con(total: -500, suma: 100, pedidos: 1).saldosNoDanElTotal, isTrue);
    });
  });
}

// La cuenta de la deuda con la casa editora hecha en el teléfono (HU-CTA-002, #671): la misma regla que
// `mi_deuda_con_la_casa_editora()` del servidor (backend-supabase 0164, 0165 y 0168), caso por caso.
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:colportores_mobile/features/cuenta/domain/services/calculador_de_la_deuda.dart';
import 'package:flutter_test/flutter_test.dart';

final _ahora = DateTime.utc(2026, 11, 20, 12);

PedidoDeLaDeuda _pedido(
  String id,
  DateTime fecha, {
  required int monto,
  int? numero,
  List<LineaDePedido> lineas = const [],
}) => PedidoDeLaDeuda(
  pedidoId: id,
  fechaPedido: fecha,
  montoCentavos: monto,
  numero: numero,
  lineas: lineas,
);

InsumosDeLaDeuda _insumos({
  int deuda = 0,
  List<CambioDeLaDeuda> historial = const [],
  List<PedidoDeLaDeuda> pedidos = const [],
  int depositos = 0,
  int tarjetas = 0,
}) => InsumosDeLaDeuda(
  deudaTotalCentavos: deuda,
  historial: historial,
  pedidos: pedidos,
  depositosValidadosCentavos: depositos,
  tarjetasValidadasCentavos: tarjetas,
);

/// «id:monto/pagado/saldo», para comparar el reparto de una mirada.
String _resumen(DeudaConLaCasa d) => d.pedidos
    .map((p) => '${p.pedidoId}:${p.montoCentavos}/${p.pagadoCentavos}/${p.saldoCentavos}')
    .join(', ');

void main() {
  group('El reparto: lo pagado cubre primero el pedido más viejo', () {
    // Los pedidos de la colportora b1 de supabase/tests/0179: a1 14000 (02/10), a2 10000 y a3 5000 (el
    // mismo día, el número desempata) y a4 3000 (20/10).
    final pedidos = [
      _pedido('a4', DateTime.utc(2026, 10, 20, 10), monto: 3000, numero: 4),
      _pedido('a3', DateTime.utc(2026, 10, 15, 10), monto: 5000, numero: 3),
      _pedido('a1', DateTime.utc(2026, 10, 2, 10), monto: 14000, numero: 1),
      _pedido('a2', DateTime.utc(2026, 10, 15, 10), monto: 10000, numero: 2),
    ];

    test('sin pagos, cada pedido debe todo y salen del más viejo al más nuevo', () {
      final d = CalculadorDeLaDeuda.calcular(_insumos(pedidos: pedidos), ahora: _ahora);
      expect(_resumen(d), 'a1:14000/0/14000, a2:10000/0/10000, a3:5000/0/5000, a4:3000/0/3000');
      expect(d.sumaDeSaldosCentavos, 32000);
    });

    test('con 21000 en depósitos y 2000 de tarjeta: a1 entero, a2 a medias, a3 y a4 sin pagar', () {
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(deuda: 15000, pedidos: pedidos, depositos: 21000, tarjetas: 2000),
        ahora: _ahora,
      );
      expect(_resumen(d), 'a2:10000/9000/1000, a3:5000/0/5000, a4:3000/0/3000');
      expect(d.deudaTotalCentavos, 15000);
      expect(d.sumaDeSaldosCentavos, 9000);
      expect(d.depositosValidadosCentavos, 21000);
    });

    test('la tarjeta validada paga como un depósito (decisión del 04/11, «Tarjeta ped.»)', () {
      final solaTarjeta = CalculadorDeLaDeuda.calcular(
        _insumos(pedidos: pedidos, tarjetas: 14000),
        ahora: _ahora,
      );
      expect(_resumen(solaTarjeta), 'a2:10000/0/10000, a3:5000/0/5000, a4:3000/0/3000');
    });

    test('lo pagado cubre todo: no se lista ningún pedido', () {
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(pedidos: pedidos, depositos: 30000, tarjetas: 2000),
        ahora: _ahora,
      );
      expect(d.pedidos, isEmpty);
      expect(d.sumaDeSaldosCentavos, 0);
    });

    test('pagó de más: la deuda real queda negativa (a favor) y no se lista el pedido', () {
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(
          deuda: -500,
          pedidos: [_pedido('b3', DateTime.utc(2026, 10, 5), monto: 4000)],
          depositos: 4500,
        ),
        ahora: _ahora,
      );
      expect(d.deudaTotalCentavos, -500);
      expect(d.aFavor, isTrue);
      expect(d.pedidos, isEmpty);
      expect(d.depositosValidadosCentavos, 4500);
    });

    test(
      'sin cuenta el total es 0 y el saldo del pedido sale igual (b2 de supabase/tests/0179)',
      () {
        final d = CalculadorDeLaDeuda.calcular(
          _insumos(
            pedidos: [_pedido('b2', DateTime.utc(2026, 10, 5), monto: 8000)],
            depositos: 2000,
          ),
          ahora: _ahora,
        );
        expect(d.deudaTotalCentavos, 0);
        expect(_resumen(d), 'b2:8000/2000/6000');
        expect(d.saldosNoDanElTotal, isTrue);
      },
    );

    test('sin pedidos ni deuda no debe nada (33B·02)', () {
      final d = CalculadorDeLaDeuda.calcular(_insumos(), ahora: _ahora);
      expect(d.sinDeuda, isTrue);
      expect(d.deudaHace7DiasCentavos, isNull);
    });

    test('un pedido de monto 0 no se lista y no gasta lo pagado', () {
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(
          pedidos: [
            _pedido('c0', DateTime.utc(2026, 10, 1), monto: 0),
            _pedido('c1', DateTime.utc(2026, 10, 2), monto: 1000),
          ],
          depositos: 400,
        ),
        ahora: _ahora,
      );
      expect(_resumen(d), 'c1:1000/400/600');
    });

    test('dos pedidos de la misma hora y el mismo número se desempatan por id', () {
      final mismaHora = DateTime.utc(2026, 10, 1, 9);
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(
          pedidos: [
            _pedido('z', mismaHora, monto: 100, numero: 7),
            _pedido('a', mismaHora, monto: 100, numero: 7),
          ],
          depositos: 100,
        ),
        ahora: _ahora,
      );
      expect(_resumen(d), 'z:100/0/100');
    });

    test('montos de 11 cifras no se desbordan', () {
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(
          deuda: 99999999999,
          pedidos: [_pedido('h', DateTime.utc(2026, 1, 1), monto: 99999999999)],
        ),
        ahora: _ahora,
      );
      expect(d.pedidos.single.saldoCentavos, 99999999999);
    });

    test('las líneas del pedido viajan tal cual a la lista', () {
      const lineas = [
        LineaDePedido(nombre: 'Libro Dos', cantidad: 2),
        LineaDePedido(nombre: 'Libro Uno', cantidad: 6),
      ];
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(pedidos: [_pedido('d1', DateTime.utc(2026, 10, 2), monto: 14000, lineas: lineas)]),
        ahora: _ahora,
      );
      expect(d.pedidos.single.lineas, lineas);
    });
  });

  group('La deuda de hace 7 días: la última fila del historial hasta «ahora − 7 × 24 h»', () {
    CambioDeLaDeuda cambio(Duration haceCuanto, int deuda, {String id = ''}) =>
        CambioDeLaDeuda(desde: _ahora.subtract(haceCuanto), deudaCentavos: deuda, id: id);

    test('hace 10 días debía 9000 y hace 3 pasó a 15000: la de hace 7 días es 9000', () {
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(
          deuda: 15000,
          historial: [
            cambio(const Duration(days: 3), 15000),
            cambio(const Duration(days: 10), 9000),
          ],
        ),
        ahora: _ahora,
      );
      expect(d.deudaHace7DiasCentavos, 9000);
      expect(d.variacionCentavos, 6000);
    });

    test('sin ninguna fila de hace 7 días o más no hay con qué comparar (null, no «igual»)', () {
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(deuda: 15000, historial: [cambio(const Duration(days: 3), 15000)]),
        ahora: _ahora,
      );
      expect(d.deudaHace7DiasCentavos, isNull);
      expect(d.variacionCentavos, isNull);
    });

    test('una fila de exactamente 7 × 24 h cuenta; una de 7 días menos un segundo, no', () {
      final justa = CalculadorDeLaDeuda.calcular(
        _insumos(historial: [cambio(const Duration(days: 7), 100)]),
        ahora: _ahora,
      );
      expect(justa.deudaHace7DiasCentavos, 100);
      final casi = CalculadorDeLaDeuda.calcular(
        _insumos(historial: [cambio(const Duration(days: 7) - const Duration(seconds: 1), 100)]),
        ahora: _ahora,
      );
      expect(casi.deudaHace7DiasCentavos, isNull);
    });

    test('con dos filas de la misma hora gana la de id más alto', () {
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(
          historial: [
            cambio(const Duration(days: 9), 100, id: 'a'),
            cambio(const Duration(days: 9), 200, id: 'b'),
          ],
        ),
        ahora: _ahora,
      );
      expect(d.deudaHace7DiasCentavos, 200);
    });

    test('puede ser negativa (estaba a favor) o cero', () {
      final negativa = CalculadorDeLaDeuda.calcular(
        _insumos(deuda: 1000, historial: [cambio(const Duration(days: 8), -500)]),
        ahora: _ahora,
      );
      expect(negativa.deudaHace7DiasCentavos, -500);
      expect(negativa.variacionCentavos, 1500);
      final cero = CalculadorDeLaDeuda.calcular(
        _insumos(historial: [cambio(const Duration(days: 8), 0)]),
        ahora: _ahora,
      );
      expect(cero.deudaHace7DiasCentavos, 0);
    });

    test('el orden en que bajan las filas no cambia la respuesta', () {
      final a = cambio(const Duration(days: 20), 1);
      final b = cambio(const Duration(days: 10), 2);
      final c = cambio(const Duration(days: 8), 3);
      for (final orden in [
        [a, b, c],
        [c, b, a],
        [b, a, c],
      ]) {
        final d = CalculadorDeLaDeuda.calcular(_insumos(historial: orden), ahora: _ahora);
        expect(d.deudaHace7DiasCentavos, 3);
      }
    });

    test('el reloj en hora local da lo mismo que en UTC', () {
      final d = CalculadorDeLaDeuda.calcular(
        _insumos(historial: [cambio(const Duration(days: 8), 5)]),
        ahora: _ahora.toLocal(),
      );
      expect(d.deudaHace7DiasCentavos, 5);
    });
  });
}

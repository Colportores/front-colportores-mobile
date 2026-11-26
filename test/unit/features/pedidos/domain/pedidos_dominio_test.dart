// El dominio de los pedidos a la casa editora (HU-STK-009, #387): las cuentas de la pantalla, el estado, y
// los dos casos de uso (enviar y cancelar).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/armado_del_pedido.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:colportores_mobile/features/pedidos/domain/services/calculador_del_pedido.dart';
import 'package:colportores_mobile/features/pedidos/domain/usecases/cancelar_pedido_use_case.dart';
import 'package:colportores_mobile/features/pedidos/domain/usecases/enviar_pedido_use_case.dart';
import 'package:test/test.dart';

import '../../../../helpers/pedidos_falsos.dart';

EnviarPedidoParams _params({
  Map<String, int> cantidades = const {'p-salud': 4, 'p-hijos': 2, 'p-vida': 20},
  String pedidoId = 'ped-1',
  bool excede = false,
}) => EnviarPedidoParams(
  pedidoId: pedidoId,
  colportorId: 'col-1',
  cantidades: cantidades,
  productos: productosDelCanvas,
  idsDeLineas: {for (final id in cantidades.keys) id: 'l-$id'},
  excedeLimite: excede,
);

void main() {
  group('CalculadorDelPedido', () {
    test('dado lo armado, cuando se cuenta, entonces suma cantidad por precio de compra', () {
      final monto = CalculadorDelPedido.montoDe({
        'p-salud': 4,
        'p-hijos': 2,
        'p-vida': 20,
      }, productosDelCanvas);
      // 4 × 1.870 + 2 × 1.330 + 20 × 85 = 7.480 + 2.660 + 1.700 = $ 11.840 (el canvas 37A·01).
      expect(monto, 1184000);
    });

    test('dado un producto que no se puede pedir o con cero, entonces no suma', () {
      expect(CalculadorDelPedido.montoDe({'desconocido': 5, 'p-salud': 0}, productosDelCanvas), 0);
    });

    test('dada la deuda de hoy, cuando se suma el pedido, entonces es la deuda con el pedido', () {
      expect(
        CalculadorDelPedido.deudaConPedido(situacionDelCanvas(), 1184000),
        3024000,
        reason:
            r'$ 18.400 + $ 11.840 = $ 30.240 (la cuenta de la HU: «Deuda actual … con este pedido …»)',
      );
    });

    group('el límite solo avisa', () {
      test('HU: debo 10.000, límite 20.000 y pido 15.000: pasa por 5.000', () {
        const s = SituacionDelColportor(
          deudaActualCentavos: 1000000,
          porCobrarCentavos: 0,
          librosPorEntregar: 0,
          limiteDeudaCentavos: 2000000,
        );
        expect(CalculadorDelPedido.superaElLimite(s, 1500000), isTrue);
        expect(CalculadorDelPedido.superaPor(s, 1500000), 500000);
      });

      test('justo en el límite NO lo supera', () {
        const s = SituacionDelColportor(
          deudaActualCentavos: 1000000,
          porCobrarCentavos: 0,
          librosPorEntregar: 0,
          limiteDeudaCentavos: 2000000,
        );
        expect(CalculadorDelPedido.superaElLimite(s, 1000000), isFalse);
        expect(CalculadorDelPedido.superaPor(s, 1000000), 0);
        expect(CalculadorDelPedido.superaElLimite(s, 1000001), isTrue);
      });

      test('sin límite fijado no hay aviso, y un pedido vacío tampoco', () {
        expect(CalculadorDelPedido.superaElLimite(situacionDelCanvas(), 99999999), isFalse);
        expect(CalculadorDelPedido.superaElLimite(situacionDelCanvas(limitePesos: 1), 0), isFalse);
      });

      test('con una deuda a favor (negativa) cuenta con el signo', () {
        const s = SituacionDelColportor(
          deudaActualCentavos: -500000,
          porCobrarCentavos: 0,
          librosPorEntregar: 0,
          limiteDeudaCentavos: 1000000,
        );
        expect(CalculadorDelPedido.deudaConPedido(s, 1200000), 700000);
        expect(CalculadorDelPedido.superaElLimite(s, 1200000), isFalse);
      });
    });
  });

  group('EstadoDelPedido', () {
    test('un código del servidor que no conoce queda como «por autorizar»', () {
      expect(EstadoDelPedido.desdeCodigo('XYZ'), EstadoDelPedido.porAutorizar);
      expect(EstadoDelPedido.desdeCodigo('BORRADOR'), EstadoDelPedido.porAutorizar);
      expect(EstadoDelPedido.desdeCodigo('RECHAZADO'), EstadoDelPedido.rechazado);
      expect(EstadoDelPedido.desdeCodigo('CANCELADO'), EstadoDelPedido.cancelado);
    });

    test('solo se cancela lo que está por autorizar; «en camino» es autorizado o despachado', () {
      for (final e in EstadoDelPedido.values) {
        expect(e.sePuedeCancelar, e == EstadoDelPedido.porAutorizar, reason: e.name);
      }
      expect(EstadoDelPedido.autorizado.enCamino, isTrue);
      expect(EstadoDelPedido.despachado.enCamino, isTrue);
      expect(EstadoDelPedido.recibido.enCamino, isFalse);
    });
  });

  group('EnviarPedidoUseCase', () {
    late PedidosFalsos repo;
    late EnviarPedidoUseCase caso;

    setUp(() {
      repo = PedidosFalsos();
      caso = EnviarPedidoUseCase(repo, ahora: () => ahoraPedidos);
    });

    test(
      'dado un pedido armado, cuando se envía, entonces nace por autorizar con su monto',
      () async {
        final r = await caso(_params());
        final enviado = r.getOrElse(() => throw StateError('falló'));
        final p = enviado.pedido;
        expect(p.estado, EstadoDelPedido.porAutorizar);
        expect(p.id, 'ped-1');
        expect(p.colportorId, 'col-1');
        expect(p.montoCentavos, 1184000);
        expect(p.unidades, 26);
        expect(p.lineas.map((l) => (l.productoId, l.cantidad)), [
          ('p-salud', 4),
          ('p-hijos', 2),
          ('p-vida', 20),
        ]);
        expect(p.lineas.map((l) => l.precioUnitarioCentavos), [187000, 133000, 8500]);
        expect(p.auditoria.createdBy, 'col-1');
        expect(repo.enviados, hasLength(1));
      },
    );

    test(
      'dado un pedido que pasa el límite, cuando se envía, entonces se envía igual (solo avisa)',
      () async {
        final r = await caso(_params(excede: true));
        expect(r.isRight(), isTrue);
        expect(repo.enviados.single.excedeLimite, isTrue);
      },
    );

    test('dado un pedido vacío o con cantidades en cero, entonces no guarda nada', () async {
      for (final cantidades in [
        const <String, int>{},
        const {'p-salud': 0},
      ]) {
        final r = await caso(_params(cantidades: cantidades));
        expect(r.fold((f) => f, (_) => null), isA<FailurePedidoInvalido>());
      }
      expect(repo.llamadasAEnviar, 0);
    });

    test(
      'dados una cantidad negativa o de más, un producto que no se pide o un id vacío, no guarda',
      () async {
        final malos = <EnviarPedidoParams>[
          _params(cantidades: const {'p-salud': -1}),
          _params(cantidades: const {'p-salud': 1000}),
          _params(cantidades: const {'no-existe': 1}),
          _params(pedidoId: '  '),
        ];
        for (final p in malos) {
          expect((await caso(p)).isLeft(), isTrue);
        }
        expect(repo.llamadasAEnviar, 0);
      },
    );

    test('dada la cantidad tope (999), entonces entra', () async {
      expect((await caso(_params(cantidades: const {'p-salud': 999}))).isRight(), isTrue);
    });

    test('dado el mismo id enviado dos veces, entonces la segunda dice que ya estaba', () async {
      await caso(_params());
      final segunda = (await caso(_params())).getOrElse(() => throw StateError('falló'));
      expect(segunda.yaEstaba, isTrue);
      expect(repo.pedidos, hasLength(1));
    });

    test('dada una falla del repositorio, entonces la devuelve tal cual', () async {
      repo.fallasAlEnviar.add(const FailurePedidoNoGuardado(causa: 'X'));
      final r = await caso(_params());
      expect(r.fold((f) => f, (_) => null), isA<FailurePedidoNoGuardado>());
    });
  });

  group('CancelarPedidoUseCase', () {
    test(
      'dado un pedido por autorizar, cuando se cancela, entonces queda cancelado (no se borra)',
      () async {
        final repo = PedidosFalsos([pedidoDe()]);
        final caso = CancelarPedidoUseCase(repo, ahora: () => ahoraPedidos);
        final r = await caso(const CancelarPedidoParams(pedidoId: 'ped-1', colportorId: 'col-1'));
        expect(r.getOrElse(() => throw StateError('falló')).estado, EstadoDelPedido.cancelado);
        expect(repo.pedidos, hasLength(1));
      },
    );

    test('dados ids vacíos, entonces no llama al repositorio y dice que no se puede', () async {
      final repo = PedidosFalsos();
      final caso = CancelarPedidoUseCase(repo);
      final r = await caso(const CancelarPedidoParams(pedidoId: '', colportorId: 'col-1'));
      expect(r.fold((f) => f, (_) => null), isA<FailurePedidoNoCancelable>());
      expect(repo.llamadasACancelar, 0);
    });
  });
}

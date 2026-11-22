// HU-COB-004 (#166): armar el plan de cuotas y modificarlo, sin pantalla ni base.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cuota.dart';
import 'package:colportores_mobile/features/cobranzas/domain/usecases/armar_plan_de_cuotas_use_case.dart';
import 'package:colportores_mobile/features/cobranzas/domain/usecases/modificar_cuotas_use_case.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:test/test.dart';

import '../../../../helpers/plan_de_cuotas_arnes.dart';

ArmarPlanParams params({
  List<int> montos = const [83300, 83300, 83400],
  DateTime? primera,
  FrecuenciaDeCuotas frecuencia = FrecuenciaDeCuotas.semanal,
  List<String>? ids,
  String direccion = 'Mataojo 2044',
}) => ArmarPlanParams(
  ventaId: 'v-1',
  colportorId: 'col-1',
  frecuencia: frecuencia,
  primeraCuota: primera ?? DateTime(2026, 10, 26),
  montosCentavos: montos,
  idsDeLasCitas: ids ?? [for (var i = 0; i < montos.length; i++) 'q-${i + 1}'],
  direccion: direccion,
);

void main() {
  late PlanDeCuotasEnMemoria repo;
  late RecordatoriosEnMemoria recordatorios;
  // «Hoy» es el sábado 26/10 a las 9:00: la primera cuota (10:00) todavía no pasó.
  final ahora = DateTime(2026, 10, 26, 9);
  late ArmarPlanDeCuotasUseCase armar;

  setUp(() {
    repo = PlanDeCuotasEnMemoria();
    recordatorios = RecordatoriosEnMemoria();
    armar = ArmarPlanDeCuotasUseCase(repo, recordatorios, ahora: () => ahora);
  });
  tearDown(() => repo.cerrar());

  Failure? falla(Either<Failure, Object?> r) => r.fold((f) => f, (_) => null);

  group('armar el plan', () {
    test(
      'dada una venta de \$ 2.500, cuando se arma un plan semanal de 3 cuotas, se agenda una cobranza por cuota con su fecha',
      () async {
        final r = await armar(params());

        final armado = r.getOrElse(() => throw StateError('falló'));
        expect(armado.plan.cuotas, hasLength(3));
        final pedido = repo.ultimoPlan!;
        expect(pedido.cuotas.map((c) => c.fecha), [
          DateTime(2026, 10, 26, 10),
          DateTime(2026, 11, 2, 10),
          DateTime(2026, 11, 9, 10),
        ]);
        expect(pedido.cuotas.map((c) => c.montoCentavos), [83300, 83300, 83400]);
        expect(pedido.ahora, ahora);
      },
    );

    test(
      'dado un plan mensual de 2 cuotas, cuando se arma, la segunda cae el mismo día del mes siguiente',
      () async {
        await armar(params(montos: [125000, 125000], frecuencia: FrecuenciaDeCuotas.mensual));
        expect(repo.ultimoPlan!.cuotas.last.fecha, DateTime(2026, 11, 26, 10));
      },
    );

    test(
      'dado un plan armado, cuando se agenda, cada cobranza lleva su recordatorio sin el nombre del cliente',
      () async {
        final r = await armar(params());
        expect(r.getOrElse(() => throw StateError('')).sinRecordatorio, 0);
        expect(recordatorios.programados, hasLength(3));
      },
    );

    test(
      'dada una primera cuota de hoy a una hora que ya pasó, cuando se arma, esa cuota queda sin recordatorio',
      () async {
        final tarde = ArmarPlanDeCuotasUseCase(
          repo,
          recordatorios,
          ahora: () => DateTime(2026, 10, 26, 15),
        );
        final r = await tarde(params());
        expect(r.getOrElse(() => throw StateError('')).sinRecordatorio, 1);
        expect(recordatorios.programados, hasLength(2));
      },
    );

    test(
      'dados recordatorios apagados, cuando se arma, el plan se guarda igual y cuenta cuántos no suenan',
      () async {
        recordatorios.resultadoForzado = ResultadoRecordatorio.apagados;
        final r = await armar(params());
        expect(r.isRight(), isTrue);
        expect(r.getOrElse(() => throw StateError('')).sinRecordatorio, 3);
      },
    );

    test('dada una primera cuota de ayer (30A-03), cuando se arma, no se guarda nada', () async {
      final r = await armar(params(primera: DateTime(2026, 10, 25)));
      expect(falla(r), const FailurePlanDeCuotas(MotivoPlanDeCuotas.fechaPasada));
      expect(repo.pedidosDeCrear, 0);
    });

    test(
      'dada una primera cuota de hoy a las 0:00, cuando se arma, sirve: solo cuenta el día',
      () async {
        final r = await armar(params(primera: DateTime(2026, 10, 26)));
        expect(r.isRight(), isTrue);
      },
    );

    test('dada una sola cuota o 13, cuando se arma, se rechaza la cantidad', () async {
      expect(
        falla(await armar(params(montos: [250000]))),
        const FailurePlanDeCuotas(MotivoPlanDeCuotas.cantidad),
      );
      expect(
        falla(await armar(params(montos: List.filled(13, 1000)))),
        const FailurePlanDeCuotas(MotivoPlanDeCuotas.cantidad),
      );
      expect(repo.pedidosDeCrear, 0);
    });

    test('dada una cuota sin monto, cuando se arma, se rechaza antes de guardar', () async {
      expect(
        falla(await armar(params(montos: [250000, 0]))),
        const FailurePlanDeCuotas(MotivoPlanDeCuotas.montos),
      );
      expect(repo.pedidosDeCrear, 0);
    });

    test('dada una cuota mayor al saldo, cuando se arma, la persistencia la rechaza', () async {
      expect(
        falla(await armar(params(montos: [260000, 100]))),
        const FailurePlanDeCuotas(MotivoPlanDeCuotas.montos),
      );
    });

    test('dados ids de menos o vacíos, cuando se arma, no se guarda nada', () async {
      expect(falla(await armar(params(ids: ['a', 'b']))), isA<FailurePlanNoGuardado>());
      expect(falla(await armar(params(ids: ['a', ' ', 'c']))), isA<FailurePlanNoGuardado>());
      expect(repo.pedidosDeCrear, 0);
    });

    test(
      'dada una falla al guardar (30A-08), cuando se arma, no se programa ningún recordatorio y el reintento con los mismos ids sale bien',
      () async {
        repo.fallaAlCrear = const FailurePlanNoGuardado(causa: 'x');

        final primero = await armar(params());
        expect(falla(primero), isA<FailurePlanNoGuardado>());
        expect(recordatorios.programados, isEmpty);

        final segundo = await armar(params());
        expect(segundo.isRight(), isTrue);
        expect(recordatorios.programados, hasLength(3));
      },
    );

    test(
      'dado el mismo pedido dos veces, cuando se repite, el plan queda con tres cuotas',
      () async {
        await armar(params());
        final otra = await armar(params());
        expect(otra.getOrElse(() => throw StateError('')).plan.cuotas, hasLength(3));
      },
    );

    test('dada una venta con cuotas por cobrar, cuando se arma otro plan, se rechaza', () async {
      await armar(params());
      final r = await armar(params(ids: ['x-1', 'x-2', 'x-3']));
      expect(falla(r), const FailurePlanDeCuotas(MotivoPlanDeCuotas.yaArmado));
    });
  });

  group('modificar las cuotas', () {
    late ModificarCuotasUseCase modificar;

    setUp(() {
      repo = PlanDeCuotasEnMemoria(
        montoCentavos: 250000,
        cobradoCentavos: 83300,
        cuotas: [
          cuotaDe(1, dia: 2, monto: 83300, cubierta: true),
          cuotaDe(2, dia: 9, monto: 83300),
          cuotaDe(3, dia: 16, monto: 83400),
        ],
      );
      modificar = ModificarCuotasUseCase(repo, ahora: () => ahora);
    });

    test(
      'dados montos nuevos de las cuotas abiertas, cuando se guardan, se pasan a la persistencia',
      () async {
        final r = await modificar(
          const ModificarCuotasParams(
            ventaId: 'v-1',
            montosPorCuota: {'q-2': 100000, 'q-3': 66700},
          ),
        );
        expect(r.isRight(), isTrue);
        expect(repo.actual.cuotas.map((c) => c.montoCentavos), [83300, 100000, 66700]);
        expect(repo.ultimoCambio!.ahora, ahora);
      },
    );

    test('dado un pedido sin cuotas, cuando se guarda, no llega a la persistencia', () async {
      final r = await modificar(const ModificarCuotasParams(ventaId: 'v-1', montosPorCuota: {}));
      expect(falla(r), isA<FailureCuotasNoGuardadas>());
      expect(repo.pedidosDeModificar, 0);
    });

    test('dada una cuota pagada, cuando se intenta cambiar, no cambia', () async {
      await modificar(const ModificarCuotasParams(ventaId: 'v-1', montosPorCuota: {'q-1': 10}));
      expect(repo.actual.cuotas.first.montoCentavos, 83300);
    });
  });
}

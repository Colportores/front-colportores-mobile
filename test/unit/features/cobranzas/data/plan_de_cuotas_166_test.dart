// El plan de cuotas contra las tablas reales (HU-COB-004, #166): AppDatabase en memoria, mismos CHECK
// que en el dispositivo, con el servicio real de `house_status`. No hay tablas de plan ni de cuotas:
// cada cuota es una cita de cobranza con su venta y su monto previsto (decisión «Plan cuotas»).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart' show MotivoPlanDeCuotas;
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source.dart'
    show AgendaRechazadaException;
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/cambios_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/pedido_de_plan.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

/// Un cobro de [monto] centavos registrado en [creado].
Cobranza cobroDe(String id, int monto, DateTime creado, {String venta = 'v-1'}) => Cobranza(
  id: id,
  ventaId: venta,
  montoCentavos: monto,
  medio: MedioCobranza.efectivo,
  fecha: creado,
  auditoria: Auditoria(createdAt: creado, updatedAt: creado, createdBy: 'col-1'),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CuotasLocalDataSourceDrift cuotas;
  late CobranzaLocalDataSourceDrift cobros;
  late AgendaLocalDataSourceDrift agendas;

  // La venta es de \$ 2.500, hecha el 23/10; el plan se arma ese día a la tarde y se cobra después.
  final armado = DateTime.utc(2026, 10, 23, 14);
  final despues = DateTime.utc(2026, 10, 24, 12);

  NuevoPlanDeCuotas plan({
    String venta = 'v-1',
    List<int> montos = const [83300, 83300, 83400],
    String prefijo = 'q',
    DateTime? ahora,
  }) => NuevoPlanDeCuotas(
    ventaId: venta,
    colportorId: 'col-1',
    ahora: ahora ?? armado,
    cuotas: [
      for (var i = 0; i < montos.length; i++)
        NuevaCuota(
          agendaId: '$prefijo-${i + 1}',
          fecha: DateTime(2026, 10, 26 + 7 * i, 10),
          montoCentavos: montos[i],
        ),
    ],
  );

  Future<void> sembrarVenta({String id = 'v-1', int monto = 250000}) async {
    final ventas = VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    await ventas.registrar(ventaDe(id, monto: monto, talonario: 'T-$id'), [
      itemDe('i-$id', id, cantidad: 1, precio: monto),
    ]);
    encolador.encolados.clear();
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    cuotas = CuotasLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    cobros = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    agendas = AgendaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
    await sembrarVenta();
  });
  tearDown(() => db.close());

  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];
  Future<List<AgendaFila>> citas() =>
      (db.select(db.agendas)..orderBy([(a) => OrderingTerm.asc(a.id)])).get();

  Future<void> rechaza(Future<Object?> Function() f, MotivoPlanDeCuotas motivo) async {
    await expectLater(
      f,
      throwsA(isA<CuotasRechazadasException>().having((e) => e.motivo, 'motivo', motivo)),
    );
  }

  group('crear el plan (30A-01 a 30A-04)', () {
    test(
      'dada una venta de \$ 2.500, cuando se arma un plan de 3 cuotas, se agendan tres cobranzas con su monto, '
      'se encolan y la venta no cambia',
      () async {
        final creado = await cuotas.crearPlan(plan());

        final filas = await citas();
        expect(filas.map((f) => f.tipo).toSet(), {'COBRANZA'});
        expect(filas.map((f) => f.estado).toSet(), {'PROGRAMADA'});
        expect(filas.map((f) => f.montoPrevisto), [83300, 83300, 83400]);
        expect(filas.map((f) => f.ventaId).toSet(), {'v-1'});
        expect(filas.map((f) => f.espacioId).toSet(), {'esp-1'});
        expect(filas.map((f) => f.espacioPersonaId).toSet(), {'ep-1'});
        expect(cola(), ['agenda:insert', 'agenda:insert', 'agenda:insert']);
        final payload = encolador.encolados.first.payload;
        expect(payload['venta_id'], 'v-1');
        expect(payload['monto_previsto'], 83300);
        expect(payload['tipo'], 'COBRANZA');
        expect(creado.cuotas.map((c) => (c.numero, c.montoCentavos)), [
          (1, 83300),
          (2, 83300),
          (3, 83400),
        ]);
        expect(creado.venta.saldoCentavos, 250000);
        expect(creado.sePuedeArmar, isFalse);
      },
    );

    test(
      'dado un plan creado, cuando se arma, la casa se recalcula en la misma transacción',
      () async {
        await cuotas.crearPlan(plan());
        expect(await db.select(db.houseStatuses).get(), isNotEmpty);
      },
    );

    test(
      'dado un doble toque con los mismos ids, cuando se arma dos veces, no se agenda de más',
      () async {
        await cuotas.crearPlan(plan());
        encolador.encolados.clear();

        final otra = await cuotas.crearPlan(plan());

        expect(await citas(), hasLength(3));
        expect(cola(), isEmpty);
        expect(otra.cuotas, hasLength(3));
      },
    );

    test(
      'dado un fallo del encolado a mitad del plan, cuando se arma, no queda ninguna cobranza (30A-08)',
      () async {
        final roto = _EncoladorQueFallaEn(2, encolador);
        final local = CuotasLocalDataSourceDrift(
          db,
          encolador: roto,
          estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
        );

        await expectLater(local.crearPlan(plan()), throwsA(isA<StateError>()));
        expect(await citas(), isEmpty);

        // El reintento con los mismos ids sale bien.
        await cuotas.crearPlan(plan());
        expect(await citas(), hasLength(3));
      },
    );

    test('dada una venta pagada, cuando se arma un plan, se rechaza sin saldo (30A-07)', () async {
      await cobros.registrar(cobroDe('c-todo', 250000, armado));
      await rechaza(() => cuotas.crearPlan(plan()), MotivoPlanDeCuotas.sinSaldo);
      expect(await citas(), isEmpty);
    });

    test('dada una venta con cuotas por cobrar, cuando se arma otro plan, se rechaza', () async {
      await cuotas.crearPlan(plan());
      await rechaza(() => cuotas.crearPlan(plan(prefijo: 'z')), MotivoPlanDeCuotas.yaArmado);
      expect(await citas(), hasLength(3));
    });

    test('dada una venta que no existe, cuando se arma un plan, se rechaza', () async {
      await rechaza(() => cuotas.crearPlan(plan(venta: 'v-x')), MotivoPlanDeCuotas.sinVenta);
    });

    test(
      'dados montos que superan el saldo, cuando se arma, se rechaza sin agendar nada',
      () async {
        await rechaza(() => cuotas.crearPlan(plan(montos: [260000, 1])), MotivoPlanDeCuotas.montos);
        await rechaza(
          () => cuotas.crearPlan(plan(montos: [200000, 100000])),
          MotivoPlanDeCuotas.montos,
        );
        await rechaza(() => cuotas.crearPlan(plan(montos: [250000, 0])), MotivoPlanDeCuotas.montos);
        expect(await citas(), isEmpty);
      },
    );

    test('dadas más de 12 cuotas, cuando se arma, se rechaza', () async {
      await rechaza(
        () => cuotas.crearPlan(plan(montos: List.filled(13, 1000))),
        MotivoPlanDeCuotas.cantidad,
      );
      expect(await citas(), isEmpty);
    });

    test('dado un plan de 12 cuotas, cuando se arma, entra', () async {
      await cuotas.crearPlan(plan(montos: List.filled(12, 1000)));
      expect(await citas(), hasLength(12));
    });

    test(
      'dado un plan armado con saldo por cobrar, cuando se lee, el saldo no se toca y se ve cada cuota',
      () async {
        await cuotas.crearPlan(plan());
        final leido = await cuotas.leerPlan('v-1');
        expect(leido!.cuotas, hasLength(3));
        expect(leido.proxima!.numero, 1);
        expect(leido.venta.saldoCentavos, 250000);
      },
    );
  });

  group('un cobro se aplica a la cuota más próxima', () {
    setUp(() async {
      await cuotas.crearPlan(plan());
      encolador.encolados.clear();
    });

    test(
      'dado un pago parcial dentro de la cuota, cuando se registra, la cuota sigue activa con lo que falta '
      'y el cobro lleva su número',
      () async {
        await cobros.registrar(cobroDe('c-1', 30000, despues));

        final leido = (await cuotas.leerPlan('v-1'))!;
        expect(leido.cuotas.first.pagadoCentavos, 30000);
        expect(leido.cuotas.first.faltanCentavos, 53300);
        expect(leido.cuotas.first.estaCubierta, isFalse);
        expect((await db.select(db.agendas).get()).where((a) => a.estado == 'CUMPLIDA'), isEmpty);
        expect(cola(), ['cobranza:insert']);
        expect(encolador.encolados.single.payload['numero_cuota'], 1);
      },
    );

    test(
      'dado un pago que cumple la cuota completa, cuando se registra, la cuota queda CUMPLIDA y sube',
      () async {
        await cobros.registrar(cobroDe('c-1', 83300, despues));

        final primera = await (db.select(db.agendas)..where((a) => a.id.equals('q-1'))).getSingle();
        expect(primera.estado, 'CUMPLIDA');
        expect(cola(), ['cobranza:insert', 'agenda:update']);
        expect(encolador.encolados.last.payload['estado'], 'CUMPLIDA');
        final leido = (await cuotas.leerPlan('v-1'))!;
        expect(leido.cuotas.first.estaCubierta, isTrue);
        expect(leido.proxima!.numero, 2);
        expect(leido.venta.saldoCentavos, 250000 - 83300);
      },
    );

    test(
      'dado un pago de más, cuando se registra, completa la cuota y adelanta la siguiente (30A-05)',
      () async {
        await cobros.registrar(cobroDe('c-1', 100000, despues));

        final leido = (await cuotas.leerPlan('v-1'))!;
        expect(leido.cuotas.map((c) => c.estaCubierta), [true, false, false]);
        expect(leido.cuotas[1].pagadoCentavos, 16700);
        expect(encolador.encolados.first.payload['numero_cuota'], 1);
      },
    );

    test(
      'dados dos cobros seguidos, cuando se registran, el segundo ve lo que dejó el primero',
      () async {
        await cobros.registrar(cobroDe('c-1', 40000, despues));
        await cobros.registrar(cobroDe('c-2', 43300, despues.add(const Duration(minutes: 1))));

        final leido = (await cuotas.leerPlan('v-1'))!;
        expect(leido.cuotas.first.estaCubierta, isTrue);
        expect(leido.cuotas[1].pagadoCentavos, 0);
        expect(cola().where((c) => c == 'agenda:update'), hasLength(1));
      },
    );

    test(
      'dado el mismo cobro registrado dos veces, cuando se repite, no vuelve a tocar las cuotas',
      () async {
        await cobros.registrar(cobroDe('c-1', 83300, despues));
        encolador.encolados.clear();

        final otra = await cobros.registrar(cobroDe('c-1', 83300, despues));

        expect(otra.yaEstaba, isTrue);
        expect(cola(), isEmpty);
      },
    );

    test(
      'dado el pago de todo el saldo, cuando se registra, todas las cuotas quedan cumplidas',
      () async {
        await cobros.registrar(cobroDe('c-1', 250000, despues));
        final estados = (await citas()).map((a) => a.estado).toSet();
        expect(estados, {'CUMPLIDA'});
        expect((await cuotas.leerPlan('v-1'))!.venta.tieneSaldo, isFalse);
      },
    );

    test(
      'dada una venta sin plan, cuando se cobra, el pago es libre y no lleva número de cuota',
      () async {
        await sembrarVenta(id: 'v-2', monto: 100000);
        await cobros.registrar(cobroDe('c-2', 50000, despues, venta: 'v-2'));
        expect(encolador.encolados.single.payload['numero_cuota'], isNull);
      },
    );

    test(
      'dado un cobro anterior al plan, cuando se arma, no se cuenta como pago de una cuota',
      () async {
        await sembrarVenta(id: 'v-3', monto: 100000);
        await cobros.registrar(
          cobroDe('c-previo', 20000, armado.subtract(const Duration(hours: 1)), venta: 'v-3'),
        );
        await cuotas.crearPlan(plan(venta: 'v-3', montos: [40000, 40000], prefijo: 'p3'));

        final leido = (await cuotas.leerPlan('v-3'))!;
        expect(leido.cuotas.map((c) => c.pagadoCentavos), [0, 0]);
        expect(leido.venta.saldoCentavos, 80000);
      },
    );
  });

  group('modificar las cuotas (30A-09)', () {
    setUp(() async {
      await cuotas.crearPlan(plan());
      encolador.encolados.clear();
    });

    ModificacionDeCuotas cambio(Map<String, int> montos) => ModificacionDeCuotas(
      ventaId: 'v-1',
      ahora: despues,
      cambios: [
        for (final e in montos.entries) CambioDeCuota(agendaId: e.key, montoCentavos: e.value),
      ],
    );

    test(
      'dados nuevos montos, cuando se guardan, solo cambian las cuotas tocadas y suben',
      () async {
        final nuevo = await cuotas.modificarCuotas(
          cambio({'q-1': 90000, 'q-2': 80000, 'q-3': 80000}),
        );

        expect(nuevo.cuotas.map((c) => c.montoCentavos), [90000, 80000, 80000]);
        expect(cola(), ['agenda:update', 'agenda:update', 'agenda:update']);
      },
    );

    test('dados los mismos montos, cuando se guardan, no se escribe nada', () async {
      await cuotas.modificarCuotas(cambio({'q-1': 83300, 'q-2': 83300, 'q-3': 83400}));
      expect(cola(), isEmpty);
    });

    test('dada una cuota pagada, cuando se intenta cambiar, se rechaza y no cambia nada', () async {
      await cobros.registrar(cobroDe('c-1', 83300, despues));
      encolador.encolados.clear();

      await rechaza(
        () => cuotas.modificarCuotas(cambio({'q-1': 50000, 'q-2': 83300, 'q-3': 83400})),
        MotivoPlanDeCuotas.cuotaCerrada,
      );
      expect(cola(), isEmpty);
    });

    test('dada una cuota con un pago parcial, cuando se baja de lo cobrado, se rechaza', () async {
      await cobros.registrar(cobroDe('c-1', 30000, despues));
      await rechaza(
        () => cuotas.modificarCuotas(cambio({'q-1': 20000})),
        MotivoPlanDeCuotas.montos,
      );
    });

    test('dada una cuota bajada justo a lo cobrado, cuando se guarda, queda cumplida', () async {
      await cobros.registrar(cobroDe('c-1', 30000, despues));
      encolador.encolados.clear();

      await cuotas.modificarCuotas(cambio({'q-1': 30000, 'q-2': 83300, 'q-3': 136700}));

      final primera = await (db.select(db.agendas)..where((a) => a.id.equals('q-1'))).getSingle();
      expect(primera.estado, 'CUMPLIDA');
    });

    test('dados montos que juntos superan lo que falta, cuando se guardan, se rechaza', () async {
      await rechaza(
        () => cuotas.modificarCuotas(cambio({'q-1': 200000, 'q-2': 83300, 'q-3': 83400})),
        MotivoPlanDeCuotas.montos,
      );
      await rechaza(() => cuotas.modificarCuotas(cambio({'q-1': 0})), MotivoPlanDeCuotas.montos);
    });

    test('dada una cuota que no es de la venta, cuando se cambia, se rechaza', () async {
      await rechaza(
        () => cuotas.modificarCuotas(cambio({'otra': 100})),
        MotivoPlanDeCuotas.cuotaCerrada,
      );
    });
  });

  group('cancelar una cuota', () {
    setUp(() async {
      await cuotas.crearPlan(plan());
      encolador.encolados.clear();
    });

    test(
      'dada la cuota 1 cancelada, cuando se cancela, su monto pasa a las que siguen en partes iguales',
      () async {
        await agendas.cancelar('q-1', ahora: despues);

        final filas = await citas();
        expect(filas.firstWhere((a) => a.id == 'q-1').estado, 'CANCELADA');
        expect(filas.firstWhere((a) => a.id == 'q-2').montoPrevisto, 125000);
        expect(filas.firstWhere((a) => a.id == 'q-3').montoPrevisto, 125000);
        expect(cola().where((c) => c == 'agenda:update'), hasLength(3));
        final leido = (await cuotas.leerPlan('v-1'))!;
        expect(leido.cuotas.map((c) => (c.numero, c.montoCentavos)), [(1, 125000), (2, 125000)]);
      },
    );

    test(
      'dada la última cuota cancelada, cuando se cancela, no hay a quién pasarle el monto y la deuda sigue en la venta',
      () async {
        await agendas.cancelar('q-3', ahora: despues);

        final filas = await citas();
        expect(filas.firstWhere((a) => a.id == 'q-1').montoPrevisto, 83300);
        expect(filas.firstWhere((a) => a.id == 'q-2').montoPrevisto, 83300);
        expect((await cuotas.leerPlan('v-1'))!.venta.saldoCentavos, 250000);
      },
    );

    test(
      'dada la cancelación repetida, cuando se cancela dos veces, el monto pasa una sola vez',
      () async {
        await agendas.cancelar('q-1', ahora: despues);
        encolador.encolados.clear();
        await agendas.cancelar('q-1', ahora: despues);

        expect(cola(), isEmpty);
        final filas = await citas();
        expect(filas.firstWhere((a) => a.id == 'q-2').montoPrevisto, 125000);
      },
    );

    test(
      'dadas las últimas cuotas canceladas, cuando se cancelan, no hay a quién pasarle nada y la primera no cambia',
      () async {
        await agendas.cancelar('q-3', ahora: despues);
        await agendas.cancelar('q-2', ahora: despues);
        // Sin cuotas detrás, ninguna cambió.
        expect((await citas()).firstWhere((a) => a.id == 'q-1').montoPrevisto, 83300);
      },
    );
  });

  group('reprogramar una cuota', () {
    setUp(() async {
      await cuotas.crearPlan(plan());
      encolador.encolados.clear();
    });

    CambiosDeAgenda cambios(String id, {TipoAgenda tipo = TipoAgenda.cobranza}) => CambiosDeAgenda(
      agendaId: id,
      tipo: tipo,
      fechaProgramada: DateTime.utc(2026, 11, 3, 13),
      idNota: 'nota-1',
    );

    test(
      'dada una cuota, cuando se cambia el día, se reprograma y conserva su venta y su monto',
      () async {
        await agendas.modificar(cambios('q-2'), ahora: despues);

        final fila = await (db.select(db.agendas)..where((a) => a.id.equals('q-2'))).getSingle();
        expect(fila.fechaProgramada, DateTime.utc(2026, 11, 3, 13));
        expect(fila.montoPrevisto, 83300);
        expect(fila.ventaId, 'v-1');
        expect(cola(), ['agenda:update']);
      },
    );

    test(
      'dada una cuota, cuando se intenta pasar a entrevista, se rechaza y no cambia nada',
      () async {
        await expectLater(
          agendas.modificar(cambios('q-2', tipo: TipoAgenda.entrevista), ahora: despues),
          throwsA(isA<AgendaRechazadaException>()),
        );
        expect(cola(), isEmpty);
      },
    );
  });

  test(
    'dado un cambio en las cuotas, cuando se observa el plan, emite el estado nuevo sin recargar',
    () async {
      final vistos = <int>[];
      final sub = cuotas.observarPlan('v-1').listen((p) => vistos.add(p?.cuotas.length ?? -1));
      await pumpEventQueue();
      await cuotas.crearPlan(plan());
      await pumpEventQueue();
      await sub.cancel();

      expect(vistos.first, 0);
      expect(vistos.last, 3);
    },
  );

  test('el estado de una cita cumplida por un plan no cambia el de las demás ventas', () async {
    await sembrarVenta(id: 'v-2', monto: 100000);
    await cuotas.crearPlan(plan());
    await cuotas.crearPlan(plan(venta: 'v-2', montos: [50000, 50000], prefijo: 'w'));
    await cobros.registrar(cobroDe('c-1', 83300, despues));

    final cumplidas = (await citas()).where((a) => a.estado == EstadoAgenda.cumplida.codigo);
    expect(cumplidas.map((a) => a.id), ['q-1']);
  });
}

/// Un encolador que falla al llegar al encolado número [cuando].
final class _EncoladorQueFallaEn implements EncoladorSync {
  _EncoladorQueFallaEn(this.cuando, this.real);

  final int cuando;
  final EncoladorSync real;
  var _vistos = 0;

  @override
  Future<void> encolar(
    String entidad,
    OperacionSync operacion,
    Map<String, Object?> payload,
  ) async {
    _vistos++;
    if (_vistos == cuando) throw StateError('sin cola');
    await real.encolar(entidad, operacion, payload);
  }
}

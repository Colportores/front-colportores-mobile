// Anular un cobro reabre las cuotas que dejan de estar cubiertas (decisión «Anular cuota», Cristian
// 24/11, #769): AppDatabase en memoria, con el servicio real de `house_status`. Las cuotas son citas de
// cobranza (decisión «Plan cuotas»): al anular, las que el cobro cubría vuelven a `PROGRAMADA` con su
// fecha y suben como cualquier cita, así la agenda y el saldo dicen lo mismo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/detalle_del_cobro.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/pedido_de_plan.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

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

  // Venta de $ 2.500 hecha el 23/10; el plan (3 cuotas) se arma ese día y se cobra el 24/10.
  final armado = DateTime.utc(2026, 10, 23, 14);
  final c1 = DateTime.utc(2026, 10, 24, 12);
  final c2 = DateTime.utc(2026, 10, 24, 13);
  final anulacion = DateTime.utc(2026, 10, 24, 18);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    cuotas = CuotasLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    cobros = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
    await VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas).registrar(
      ventaDe('v-1', monto: 250000, talonario: 'T-1'),
      [itemDe('i-1', 'v-1', cantidad: 1, precio: 250000)],
    );
    await cuotas.crearPlan(
      NuevoPlanDeCuotas(
        ventaId: 'v-1',
        colportorId: 'col-1',
        ahora: armado,
        cuotas: [
          for (var i = 0; i < 3; i++)
            NuevaCuota(
              agendaId: 'q-${i + 1}',
              fecha: DateTime(2026, 10, 26 + 7 * i, 10),
              montoCentavos: const [83300, 83300, 83400][i],
            ),
        ],
      ),
    );
    encolador.encolados.clear();
  });
  tearDown(() => db.close());

  Future<AnulacionHecha> anular(String id, {DateTime? ahora}) => cobros.anular(
    cobranzaId: id,
    motivo: MotivoDeAnulacion.montoEquivocado,
    colportorId: 'col-1',
    ahora: ahora ?? anulacion,
  );

  Future<List<String>> estados() async => [
    for (final f in await (db.select(db.agendas)..orderBy([(a) => OrderingTerm.asc(a.id)])).get())
      f.estado,
  ];

  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];

  group('anular un cobro con plan de cuotas', () {
    test('la cuota que cubría vuelve a «Programada» con su fecha y su monto, y sube', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      expect(await estados(), ['CUMPLIDA', 'PROGRAMADA', 'PROGRAMADA']);
      final fechaAntes = (await cuotas.leerPlan('v-1'))!.cuotas.first.fecha;
      encolador.encolados.clear();

      await anular('c-1');

      expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'PROGRAMADA']);
      final plan = (await cuotas.leerPlan('v-1'))!;
      expect(plan.cuotas.first.fecha, fechaAntes, reason: 'conserva su fecha');
      expect(plan.cuotas.first.montoCentavos, 83300);
      expect(plan.cuotas.first.pagadoCentavos, 0);
      expect(plan.venta.saldoCentavos, 250000, reason: 'la agenda y el saldo dicen lo mismo');
      expect(cola(), contains('agenda:update'));
      expect(cola(), contains('cobranza:update'));
      final agenda = encolador.encolados.firstWhere((c) => c.entidad == 'agenda').payload;
      expect(agenda['id'], 'q-1');
      expect(agenda['estado'], 'PROGRAMADA');
    });

    test(
      'el cobro que cubría dos cuotas las reabre a las dos, y una tercera sigue igual',
      () async {
        await cobros.registrar(cobroDe('c-1', 166600, c1));
        expect(await estados(), ['CUMPLIDA', 'CUMPLIDA', 'PROGRAMADA']);
        encolador.encolados.clear();

        await anular('c-1');

        expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'PROGRAMADA']);
        expect(cola().where((e) => e == 'agenda:update'), hasLength(2));
      },
    );

    test('un cobro grande reparte lo que sobra: al anularlo, la parcial también vuelve', () async {
      await cobros.registrar(cobroDe('c-1', 100000, c1));
      expect(await estados(), ['CUMPLIDA', 'PROGRAMADA', 'PROGRAMADA']);

      await anular('c-1');

      final plan = (await cuotas.leerPlan('v-1'))!;
      expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'PROGRAMADA']);
      expect(plan.cuotas.map((c) => c.pagadoCentavos), [0, 0, 0]);
    });

    test('con dos cobros, anular uno deja cubierta la cuota que el otro todavía paga', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      await cobros.registrar(cobroDe('c-2', 83300, c2));
      expect(await estados(), ['CUMPLIDA', 'CUMPLIDA', 'PROGRAMADA']);

      await anular('c-1');

      expect(await estados(), ['CUMPLIDA', 'PROGRAMADA', 'PROGRAMADA']);
      final plan = (await cuotas.leerPlan('v-1'))!;
      expect(plan.cuotas.first.estaCubierta, isTrue);
      expect(plan.venta.saldoCentavos, 250000 - 83300);
    });

    test('dos anulaciones seguidas reabren cada una lo suyo, sin pisarse ni repetirse', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      await cobros.registrar(cobroDe('c-2', 83300, c2));
      encolador.encolados.clear();

      await anular('c-2');
      expect(await estados(), ['CUMPLIDA', 'PROGRAMADA', 'PROGRAMADA']);
      await anular('c-1');

      expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'PROGRAMADA']);
      expect(cola().where((e) => e == 'agenda:update'), hasLength(2));
      expect((await cuotas.leerPlan('v-1'))!.venta.saldoCentavos, 250000);
    });

    test('anular dos veces el mismo cobro no escribe de nuevo ni reabre otra cuota', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      await cobros.registrar(cobroDe('c-2', 83300, c2));
      await anular('c-1');
      encolador.encolados.clear();

      final otra = await anular('c-1', ahora: anulacion.add(const Duration(minutes: 5)));

      expect(otra.yaEstaba, isTrue);
      expect(encolador.encolados, isEmpty);
      expect(await estados(), ['CUMPLIDA', 'PROGRAMADA', 'PROGRAMADA']);
    });

    test('un cobro que no completó ninguna cuota no reabre nada ni encola citas', () async {
      await cobros.registrar(cobroDe('c-1', 30000, c1));
      encolador.encolados.clear();

      await anular('c-1');

      expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'PROGRAMADA']);
      expect(cola(), isNot(contains('agenda:update')));
    });

    test('una cita cerrada de otro modo (sin cobros que la expliquen) no se toca', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      await (db.update(
        db.agendas,
      )..where((a) => a.id.equals('q-3'))).write(const AgendasCompanion(estado: Value('CUMPLIDA')));
      encolador.encolados.clear();

      await anular('c-1');

      expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'CUMPLIDA']);
    });

    test('si falla el encolado de la cita, ni el cobro ni las cuotas cambian', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      encolador
        ..encolados.clear()
        ..fallarCon = StateError('motor apagado')
        ..fallarDespuesDe = 1;

      await expectLater(anular('c-1'), throwsA(isA<StateError>()));

      final cobro = await (db.select(db.cobranzas)..where((c) => c.id.equals('c-1'))).getSingle();
      expect(cobro.anuladoAt, isNull, reason: 'todo o nada');
      expect(await estados(), ['CUMPLIDA', 'PROGRAMADA', 'PROGRAMADA']);

      // El botón vuelve a servir: con el motor andando, se anula.
      encolador.fallarCon = null;
      await anular('c-1');
      expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'PROGRAMADA']);
    });

    test('una venta sin plan se anula como siempre', () async {
      await VentaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
      ).registrar(ventaDe('v-2', monto: 100000, talonario: 'T-2'), [
        itemDe('i-2', 'v-2', cantidad: 1, precio: 100000),
      ]);
      await cobros.registrar(cobroDe('c-9', 50000, c1, venta: 'v-2'));
      encolador.encolados.clear();

      await anular('c-9');

      expect(cola().where((e) => e.startsWith('cobranza') || e.startsWith('agenda')), [
        'cobranza:update',
      ]);
      expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'PROGRAMADA']);
    });
  });
}

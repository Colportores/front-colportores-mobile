// El cobro que baja anulado del panel reabre las cuotas que deja sin cubrir (decisiones «Anular cuota» y
// «Anul. al tel», #769): AppDatabase en memoria, con el servicio real de `house_status`. Las cuotas son citas de
// cobranza (decisión «Plan cuotas»): al anular, las que el cobro cubría vuelven a `PROGRAMADA` con su
// fecha y suben como cualquier cita, así la agenda y el saldo dicen lo mismo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/services/casas_de_cobros_bajados.dart';
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
  late CasasDeCobrosBajados casasBajadas;

  // Venta de $ 2.500 hecha el 23/10; el plan (3 cuotas) se arma ese día y se cobra el 24/10.
  final armado = DateTime.utc(2026, 10, 23, 14);
  final c1 = DateTime.utc(2026, 10, 24, 12);
  final c2 = DateTime.utc(2026, 10, 24, 13);
  final anulacion = DateTime.utc(2026, 10, 24, 18);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    casasBajadas = CasasDeCobrosBajados(db, encolador: encolador);
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

  /// La coordinación anula [id] desde el panel: el cobro baja del servidor con `anulado_at`.
  Future<void> bajaAnulado(String id) async {
    await db.customStatement(
      'UPDATE cobranza SET anulado_at = ${anulacion.millisecondsSinceEpoch}, '
      "motivo_anulacion = 'Monto equivocado' WHERE id = '$id'",
    );
    await casasBajadas({
      'cobranza': [
        {'id': id, 'anulado_at': anulacion.toIso8601String()},
      ],
    });
  }

  Future<List<String>> estados() async => [
    for (final f in await (db.select(db.agendas)..orderBy([(a) => OrderingTerm.asc(a.id)])).get())
      f.estado,
  ];

  List<String> citas() => [
    for (final c in encolador.encolados)
      if (c.entidad == 'agenda') '${c.payload['id']}:${c.payload['estado']}',
  ];

  group('el cobro que baja anulado del panel', () {
    test('reabre la cuota que cubría, con su fecha, y la cita sube PROGRAMADA', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      final fecha = (await cuotas.leerPlan('v-1'))!.cuotas.first.fecha;
      encolador.encolados.clear();

      await bajaAnulado('c-1');

      expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'PROGRAMADA']);
      expect((await cuotas.leerPlan('v-1'))!.cuotas.first.fecha, fecha);
      expect(citas(), ['q-1:PROGRAMADA']);
      expect((await cuotas.leerPlan('v-1'))!.venta.saldoCentavos, 250000);
    });

    test('si baja dos veces no escribe de nuevo', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      await bajaAnulado('c-1');
      encolador.encolados.clear();

      await bajaAnulado('c-1');

      expect(citas(), isEmpty);
      expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'PROGRAMADA']);
    });

    test('una cuota que otro cobro sigue cubriendo queda «Cumplida»', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      await cobros.registrar(cobroDe('c-2', 83300, c2));
      encolador.encolados.clear();

      await bajaAnulado('c-2');

      expect(await estados(), ['CUMPLIDA', 'PROGRAMADA', 'PROGRAMADA']);
      expect(citas(), ['q-2:PROGRAMADA']);
    });

    test('lo que Ana anuló en su teléfono y vuelve en el pull no reabre nada otra vez', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      await cobros.anular(
        cobranzaId: 'c-1',
        motivo: MotivoDeAnulacion.montoEquivocado,
        colportorId: 'col-1',
        ahora: anulacion,
      );
      encolador.encolados.clear();

      await casasBajadas({
        'cobranza': [
          {'id': 'c-1', 'anulado_at': anulacion.toIso8601String()},
        ],
      });

      expect(citas(), isEmpty);
      expect(await estados(), ['PROGRAMADA', 'PROGRAMADA', 'PROGRAMADA']);
    });

    test('si falla el encolado no lanza y el cobro queda anulado', () async {
      await cobros.registrar(cobroDe('c-1', 83300, c1));
      encolador
        ..encolados.clear()
        ..fallarCon = StateError('motor apagado');

      await bajaAnulado('c-1');

      expect(await estados(), [
        'CUMPLIDA',
        'PROGRAMADA',
        'PROGRAMADA',
      ], reason: 'no se pierde nada');
      final cobro = await (db.select(db.cobranzas)..where((c) => c.id.equals('c-1'))).getSingle();
      expect(cobro.anuladoAt, isNotNull);
    });
  });
}

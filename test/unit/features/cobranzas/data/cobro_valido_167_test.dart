// Qué cobro cuenta (HU-COB-005, decisión «una sola forma de hacer cada cosa»): el saldo y el color
// de la casa leen lo cobrado por `CobroValido`, la misma definición. Hoy el color no cambia con lo
// cobrado (la entrega llega con #430), así que además de comparar lecturas se cuida que el
// actualizador de la casa no vuelva a armar la suya.
import 'dart:io';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobro_valido.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

Cobranza _cobro(String id, int monto) => Cobranza(
  id: id,
  ventaId: 'v-1',
  montoCentavos: monto,
  medio: MedioCobranza.efectivo,
  fecha: t0,
  auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late CobranzaLocalDataSourceDrift local;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    final encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
    await VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: casas,
    ).registrar(ventaDe('v-1', monto: 150000), [itemDe('i-1', 'v-1', cantidad: 1, precio: 150000)]);
  });
  tearDown(() => db.close());

  test('lo cobrado, el saldo de la venta y el saldo reactivo cuentan los mismos cobros, también '
      'cuando uno se da de baja', () async {
    await local.registrar(_cobro('c-1', 50000));
    await local.registrar(_cobro('c-2', 30000));

    Future<void> mirar(int cobrado) async {
      final venta = (await local.ventaConSaldo('v-1'))!;
      expect(await CobroValido.cobradoDe(db, 'v-1'), cobrado);
      expect(venta.cobradoCentavos, cobrado);
      expect(await local.observarSaldoDePersona('per-1').first, 150000 - cobrado);
    }

    await mirar(80000);
    await db.customUpdate(
      'UPDATE cobranza SET deleted_at = 1 WHERE id = ?',
      variables: const [Variable<String>('c-2')],
      updates: {db.cobranzas},
    );
    await mirar(50000);
  });

  test('sin cobros, o con una venta que no existe, lo cobrado es 0', () async {
    expect(await CobroValido.cobradoDe(db, 'v-1'), 0);
    expect(await CobroValido.cobradoDe(db, 'v-9'), 0);
  });

  test('el color de la casa no arma su propia condición de cobro: usa CobroValido', () {
    final fuente = File(
      'lib/features/mapa/data/services/house_status_updater_drift.dart',
    ).readAsStringSync();

    expect(fuente, contains('CobroValido.cobradoDe'));
    expect(fuente, isNot(contains('cobranzas.deletedAt')));
    expect(fuente, isNot(contains('cobranzas.monto')));
  });
}

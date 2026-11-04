// QA #431, decisión del 04/11 (P2 del QA): «En mano» = lo cobrado en efectivo menos los depósitos vivos
// por validar o validados (no los rechazados), sin bajar de cero; lo mismo en el detalle de Mi plata y
// en el total de Mi Cuenta. Corre con `--dart-define=QA_HALLAZGOS=true` mientras la decisión no esté
// aplicada.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_sync_meta.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/detalle_de_mi_plata_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/resumen_de_cuenta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

final _ahora = DateTime.utc(2026, 10, 30, 12);
final _dia20 = DateTime.utc(2026, 10, 20, 15);

int _ms(DateTime f) => f.toUtc().millisecondsSinceEpoch;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late CobranzaLocalDataSourceDrift cobranzas;
  late DetalleDeMiPlataLocalDataSourceDrift local;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    final encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    cobranzas = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    final ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    local = DetalleDeMiPlataLocalDataSourceDrift(db, cobranzas: cobranzas);
    await sembrarEdificio(db);
    await ventas.registrar(
      ventaDe(
        'v-1',
        monto: 800000,
        fecha: _dia20,
        talonario: 'T-v-1',
        colportor: 'col-1',
        vinculo: 'ep-1',
      ),
      [itemDe('i-v-1', 'v-1', productoId: 'p-v-1', cantidad: 1, precio: 800000)],
    );
    // $ 5.000 cobrados en efectivo.
    await cobranzas.registrar(
      Cobranza(
        id: 'c-1',
        ventaId: 'v-1',
        montoCentavos: 500000,
        medio: MedioCobranza.efectivo,
        fecha: _dia20,
        auditoria: Auditoria(createdAt: _dia20, updatedAt: _dia20, createdBy: 'col-1'),
      ),
    );
    await DriftSyncMeta(db).write(lastPullAt: _ahora);
  });
  tearDown(() => db.close());

  Future<void> depositar(
    String id,
    int centavos, {
    DateTime? validadoEn,
    DateTime? rechazadoEn,
  }) => db.customStatement(
    'INSERT INTO deposito (id, monto, fecha, destino, concepto, campania_id, ticket_id, '
    'validado_en, rechazado_en, created_at, updated_at, deleted_at) '
    "VALUES ('$id', $centavos, ${_ms(_dia20)}, 'RETIRO_COORDINADOR', 'CASA_EDITORA', NULL, NULL, "
    '${validadoEn == null ? 'NULL' : _ms(validadoEn)}, '
    '${rechazadoEn == null ? 'NULL' : _ms(rechazadoEn)}, 1, 1, NULL)',
  );

  Future<(int, int)> enMano() async {
    final detalle = await local.leer('col-1');
    final resumen = await ResumenDeCuentaLocalDataSourceDrift(
      db,
      cobranzas: cobranzas,
      ahora: () => _ahora,
    ).leer('col-1');
    return (detalle.enManoCentavos, resumen.enMano.totalCentavos);
  }

  group('«En mano» resta lo depositado (decisión del 04/11)', () {
    test('sin depósitos, todo el efectivo cobrado está en mano', () async {
      expect(await enMano(), (500000, 500000));
    });

    // skip: QA #431 — «En mano» no resta los depósitos por validar ni los validados.
    test(
      'un depósito por validar y uno validado bajan «En mano» en el detalle y en Mi Cuenta',
      () async {
        await depositar('d-1', 100000);
        await depositar('d-2', 150000, validadoEn: _dia20);

        expect(await enMano(), (250000, 250000));
      },
      skip: !_hallazgos,
    );

    test('un depósito rechazado no baja «En mano»: la plata vuelve', () async {
      await depositar('d-1', 100000, rechazadoEn: _dia20);

      expect(await enMano(), (500000, 500000));
    });

    // skip: QA #431 — «En mano» no resta los depósitos.
    test('si se depositó más de lo cobrado, «En mano» queda en cero y no negativo', () async {
      await depositar('d-1', 900000, validadoEn: _dia20);

      expect(await enMano(), (0, 0));
    }, skip: !_hallazgos);
  });
}

// QA de «Venta crece» (HU-VEN-001, #693), privacidad (checklist 8): ni el motivo del monto ni un
// nombre llegan a los logs, a la falla ni al `toString()` de lo que viaja, aunque la base falle.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/repositories/venta_que_crece_repository_impl.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_abierta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

const _motivo = 'descuento a Pedro Gómez, cédula 1.234.567-8';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late MemoryOutput salida;
  late VentaQueCreceRepositoryImpl repo;

  String logs() => salida.buffer.expand((e) => e.lines).join('\n');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    final encolador = EncoladorSyncEnMemoria();
    final local = VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    await sembrarCasa(db);
    await local.registrar(ventaDe('v-39', talonario: '0039', monto: 150000), [
      itemDe('i-v-39', 'v-39'),
    ]);
    salida = MemoryOutput();
    repo = VentaQueCreceRepositoryImpl(
      local,
      logger: AppLogger(
        logger: Logger(level: Level.all, printer: SimplePrinter(), output: salida),
      ),
    );
  });
  tearDown(() => db.close());

  VentaItem nuevo() {
    final t = DateTime.utc(2026, 11, 11, 12);
    return VentaItem(
      id: 'n-1',
      ventaId: 'v-39',
      productoId: 'prod-2',
      cantidad: 1,
      precioUnitarioCentavos: 40000,
      subtotalCentavos: 40000,
      auditoria: Auditoria(createdAt: t, updatedAt: t, createdBy: 'col-1'),
    );
  }

  test('si la base falla al sumar, ni la falla ni el log llevan el motivo ni un nombre', () async {
    await db.customStatement('DROP TABLE venta_item');

    final r = await repo.sumar(
      'v-39',
      [nuevo()],
      numeroTalonario: '0039',
      sumadoCentavos: 35000,
      ahora: DateTime.utc(2026, 11, 11, 12),
      motivoMontoManual: _motivo,
      diferenciaCentavos: -5000,
    );

    final falla = r.fold((f) => f, (_) => null);
    expect(falla, isA<FailureVentaNoGuardada>());
    final texto = '${falla!.mensaje} ${falla.toString()} ${falla.props} ${logs()}';
    expect(texto, isNot(contains('Pedro')));
    expect(texto, isNot(contains('1.234.567')));
    expect(texto, isNot(contains('cédula')));
    expect(logs(), contains('VENTA_CRECE_FAIL'));
  });

  test('la venta cerrada se loguea sin motivo ni nombres', () async {
    await db.customStatement("UPDATE venta SET deleted_at = 1 WHERE id = 'v-39'");

    final r = await repo.sumar(
      'v-39',
      [nuevo()],
      numeroTalonario: '0039',
      sumadoCentavos: 35000,
      ahora: DateTime.utc(2026, 11, 11, 12),
      motivoMontoManual: _motivo,
      diferenciaCentavos: -5000,
    );

    expect(r.fold((f) => f, (_) => null), isA<FailureVentaCerrada>());
    expect(logs(), isNot(contains('Pedro')));
    expect(logs(), isNot(contains('1.234.567')));
  });

  test('toString de lo que viaja no imprime el motivo ni los textos', () {
    final suma = SumaALaVenta(
      sumaId: 'n-1',
      colportorId: 'col-1',
      venta: VentaAbierta(
        ventaId: 'v-39',
        espacioPersonaId: 'ep-1',
        numeroTalonario: '0039',
        fecha: DateTime.utc(2026, 10, 23),
        montoTotalCentavos: 120000,
        cobradoCentavos: 0,
        motivoMontoManual: _motivo,
        descripcion: 'Libro de Pedro Gómez',
      ),
      lineas: const [],
      sumadoACobrarCentavos: 35000,
      motivoMontoManual: _motivo,
    );

    for (final t in [suma.toString(), suma.venta.toString()]) {
      expect(t, isNot(contains('Pedro')));
      expect(t, isNot(contains('1.234.567')));
    }
  });
}

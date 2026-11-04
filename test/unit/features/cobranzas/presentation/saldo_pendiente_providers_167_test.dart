// El cableado del saldo pendiente (HU-COB-005, #167): los providers siguen la DB local y se
// actualizan solos al registrar un cobro; sin DB, o con la base ilegible, fallan con
// `FailureSaldoNoDisponible` en lugar de mostrar 0.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/repositories/saldo_pendiente_repository_impl.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

/// La DB «abierta» sin cifrado ni helper: los providers solo necesitan el `AppDatabase`.
class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;
}

Cobranza _cobro(String id, int monto) => Cobranza(
  id: id,
  ventaId: 'v-1',
  montoCentavos: monto,
  medio: MedioCobranza.efectivo,
  fecha: t0,
  auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
);

/// Espera a que se cumpla [condicion] (las lecturas de Drift terminan en otra vuelta).
Future<void> _hasta(bool Function() condicion) async {
  for (var i = 0; i < 400 && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condicion(), isTrue);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    await sembrarCasa(db);
    final ventas = VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    await ventas.registrar(ventaDe('v-1', monto: 150000), [
      itemDe('i-1', 'v-1', cantidad: 1, precio: 150000),
    ]);
  });
  tearDown(() => db.close());

  ProviderContainer armar({bool conDb = true}) {
    final c = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(conDb ? db : null)),
        encoladorSyncProvider.overrideWithValue(encolador),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('los cuatro cortes se actualizan solos al registrar un cobro, sin recargar', () async {
    final c = armar();
    final venta = c.listen(saldoDeLaVentaProvider('v-1'), (_, _) {});
    final persona = c.listen(saldoDeLaPersonaProvider('per-1'), (_, _) {});
    final ubicacion = c.listen(saldoDeLaUbicacionProvider('ub-1'), (_, _) {});
    final total = c.listen(saldoTotalDelColportorProvider('col-1'), (_, _) {});
    await _hasta(
      () => [persona, ubicacion, total, venta].every((s) => s.read() is AsyncData<Object?>),
    );
    expect(persona.read().value, 150000);

    final r = await c.read(cobranzaRepositoryProvider).registrar(_cobro('c-1', 80000));

    expect(r.isRight(), isTrue);
    await _hasta(() => persona.read().value == 70000);
    await _hasta(() => ubicacion.read().value == 70000);
    await _hasta(() => total.read().value == 70000);
    await _hasta(() => venta.read().value?.saldoCentavos == 70000);
  });

  test('sin la DB abierta, cada stream falla con FailureSaldoNoDisponible y no emite 0', () async {
    final c = armar(conDb: false);
    final persona = c.listen(saldoDeLaPersonaProvider('per-1'), (_, _) {});
    final venta = c.listen(saldoDeLaVentaProvider('v-1'), (_, _) {});
    final ubicacion = c.listen(saldoDeLaUbicacionProvider('ub-1'), (_, _) {});
    final total = c.listen(saldoTotalDelColportorProvider('col-1'), (_, _) {});

    await _hasta(
      () => [persona, venta, ubicacion, total].every((s) => s.read() is AsyncError<Object?>),
    );
    for (final s in [persona, venta, ubicacion, total]) {
      expect(s.read().error, isA<FailureSaldoNoDisponible>());
      expect(s.read().hasValue, isFalse);
    }
  });

  test('con la base ilegible, el error llega como FailureSaldoNoDisponible', () async {
    final local = CobranzaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    final repo = SaldoPendienteRepositoryImpl(local, logger: loggerMudo());
    await db.customStatement('DROP TABLE cobranza');

    for (final stream in [
      repo.observarDePersona('per-1'),
      repo.observarDeUbicacion('ub-1'),
      repo.observarTotal('col-1'),
      repo.observarVenta('v-1'),
    ]) {
      await expectLater(stream, emitsError(isA<FailureSaldoNoDisponible>()));
    }
  });

  test('FailureSaldoNoDisponible dice qué pasó y qué hacer', () {
    const falla = FailureSaldoNoDisponible();

    expect(falla.codigo, 'COBRO_SALDO_NO_DISPONIBLE');
    expect(falla.mensaje, contains('No pudimos calcular lo que te deben'));
    expect(falla.mensaje, contains('siguen guardados'));
    expect(falla.mensaje, contains('cerrá y abrí la app'));
  });
}

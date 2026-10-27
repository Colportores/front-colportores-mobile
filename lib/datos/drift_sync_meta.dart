import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import '../core/database/app_database.dart';
import 'sync_queue_table.dart';

part 'drift_sync_meta.g.dart';

/// [SyncMetaPort] sobre `sync_meta` ([SyncMetas]): las fechas y la red que la vista de estado de
/// sync muestra después de reiniciar el celular (HU-SYNC-007, #486).
///
/// Lo único que garantiza que se porte como `InMemorySyncMeta` —contra el que se verificó el
/// motor— es `runSyncMetaContract`, que corre en `test/unit/datos/drift_sync_meta_test.dart`.
@DriftAccessor(tables: [SyncMetas])
final class DriftSyncMeta extends DatabaseAccessor<AppDatabase>
    with _$DriftSyncMetaMixin
    implements SyncMetaPort {
  DriftSyncMeta(super.attachedDatabase);

  static const _ultimaBajada = 'last_pull_at';
  static const _ultimoRespaldo = 'last_backup_at';
  static const _ultimoEnvio = 'last_push_at';
  static const _redDelEnvio = 'last_push_network';

  @override
  Future<SyncMeta> read() async {
    final filas = {for (final f in await select(syncMetas).get()) f.clave: f.valor};
    return SyncMeta(
      lastPullAt: _fecha(filas[_ultimaBajada]),
      lastBackupAt: _fecha(filas[_ultimoRespaldo]),
      lastPushAt: _fecha(filas[_ultimoEnvio]),
      lastPushNetwork: SyncNetwork.fromWire(filas[_redDelEnvio]),
    );
  }

  @override
  Future<void> write({
    DateTime? lastPullAt,
    DateTime? lastBackupAt,
    DateTime? lastPushAt,
    SyncNetwork? lastPushNetwork,
  }) => transaction(() async {
    if (lastPullAt != null) await _poner(_ultimaBajada, _texto(lastPullAt));
    if (lastBackupAt != null) await _poner(_ultimoRespaldo, _texto(lastBackupAt));
    if (lastPushAt != null) {
      final guardado = _fecha(await _valorDe(_ultimoEnvio));
      // Un envío más viejo que el anotado no lo pisa, ni a su red.
      if (guardado == null || !lastPushAt.isBefore(guardado)) {
        await _poner(_ultimoEnvio, _texto(lastPushAt));
        if (lastPushNetwork == null) {
          // «No se sabe»: la red del envío anterior no es la de este.
          await (delete(syncMetas)..where((m) => m.clave.equals(_redDelEnvio))).go();
        } else {
          await _poner(_redDelEnvio, lastPushNetwork.wire);
        }
      }
    }
  });

  Future<String?> _valorDe(String clave) async =>
      (await (select(syncMetas)..where((m) => m.clave.equals(clave))).getSingleOrNull())?.valor;

  Future<void> _poner(String clave, String valor) =>
      into(syncMetas).insertOnConflictUpdate(SyncMetasCompanion.insert(clave: clave, valor: valor));

  static String _texto(DateTime fecha) => fecha.toUtc().toIso8601String();

  /// Un valor ilegible (la fila se editó a mano) es «no hay dato», no una excepción: la vista de
  /// estado tiene que abrir igual.
  static DateTime? _fecha(String? texto) =>
      texto == null ? null : DateTime.tryParse(texto)?.toUtc();
}

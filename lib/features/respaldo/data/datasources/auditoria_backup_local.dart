import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../mapa/data/datasources/audit_log_table.dart';

/// El registro de las verificaciones semanales del backup en el `audit_log` local (HU-SYNC-009).
///
/// Una fila por verificación: `backup_integrity_ok` o `backup_integrity_problem`, con el instante y,
/// si hubo problema, cuáles (o `sin_respaldos`, si no había nada que verificar). **Nunca contenido del backup**: solo el nombre de cada problema.
final class AuditoriaBackupLocal {
  AuditoriaBackupLocal(this._db);

  final AppDatabase _db;

  Future<void> registrar({
    required DateTime cuando,
    required bool hayProblema,
    Set<String> problemas = const {},
  }) async {
    final ordenados = problemas.toList()..sort();
    await _db
        .into(_db.auditLogLocal)
        .insert(
          AuditLogLocalCompanion.insert(
            evento: hayProblema
                ? EventoAuditoriaLocal.backupIntegridadProblema
                : EventoAuditoriaLocal.backupIntegridadOk,
            uuid: EventoAuditoriaLocal.uuidBackup,
            motivo: Value(ordenados.isEmpty ? null : ordenados.join(',')),
            creadoEn: cuando.toUtc(),
          ),
        );
  }

  /// Cuándo fue la última verificación, haya salido bien o mal. `null` si nunca se hizo.
  Future<DateTime?> ultimaVerificacion() async {
    final tabla = _db.auditLogLocal;
    final fila =
        await (_db.select(tabla)
              ..where(
                (a) => a.evento.isIn([
                  EventoAuditoriaLocal.backupIntegridadOk,
                  EventoAuditoriaLocal.backupIntegridadProblema,
                ]),
              )
              ..orderBy([(a) => OrderingTerm.desc(a.creadoEn)])
              ..limit(1))
            .getSingleOrNull();
    return fila?.creadoEn;
  }
}

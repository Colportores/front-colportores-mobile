import 'package:drift/drift.dart' show Value;

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/instante.dart';
import '../../../mapa/data/datasources/audit_log_table.dart';
import '../../domain/repositories/auditoria_push_repository.dart';

/// [AuditoriaPushRepository] sobre el `audit_log` de la DB local cifrada (solo local, no se
/// sincroniza). Una fila por push descartada, con el nombre de los campos y nunca sus valores.
final class AuditoriaPushRepositoryDrift implements AuditoriaPushRepository {
  AuditoriaPushRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<void> registrarDatosPersonales({
    required List<String> campos,
    required DateTime ahora,
  }) async {
    await _db
        .into(_db.auditLogLocal)
        .insert(
          AuditLogLocalCompanion.insert(
            evento: EventoAuditoriaLocal.pushDatosPersonales,
            uuid: EventoAuditoriaLocal.uuidPush,
            motivo: Value(campos.join(',')),
            creadoEn: instanteMs(ahora),
          ),
        );
  }
}

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/services/retencion_notas_borradas.dart';
import 'notas_table.dart';

/// La limpieza de las notas de persona borradas sobre la tabla `nota` de la DB cifrada.
///
/// **local-only — PII**: las notas no están en el sync, así que borrarlas es un `DELETE` físico y no
/// hay nada que encolar ni que avisar al servidor. Es **una sola sentencia**: o se van todas las
/// vencidas o ninguna. Solo toca `target_type = PERSONA`: las notas de un lugar (vista 39) no tienen
/// definido ese plazo.
final class NotasBorradasLocalDataSourceDrift {
  NotasBorradasLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  /// Borra las notas de persona con `deleted_at` anterior al corte de [ahora] (90 días atrás). Una
  /// nota activa (`deleted_at` nulo) nunca entra, y una restaurada a tiempo tampoco: la restauración
  /// y la limpieza son transacciones de la misma DB, así que se serializan. Devuelve cuántas borró.
  Future<int> purgarVencidas({required DateTime ahora}) {
    final corte = RetencionNotasBorradas.corte(ahora.toUtc()).millisecondsSinceEpoch;
    return (_db.delete(_db.notas)..where(
          (n) =>
              n.targetType.equals(TipoObjetivoNota.persona) &
              n.deletedAt.isNotNull() &
              n.deletedAt.isSmallerThanValue(corte),
        ))
        .go();
  }
}

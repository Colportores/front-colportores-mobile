import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/services/retencion_notas_borradas.dart';
import 'notas_table.dart';

/// La limpieza de las notas borradas de una persona o de un lugar sobre la tabla `nota` de la DB cifrada.
///
/// **local-only — PII**: las notas no están en el sync, así que borrarlas es un `DELETE` físico y no
/// hay nada que encolar ni que avisar al servidor. Es **una sola sentencia**: o se van todas las
/// vencidas o ninguna. Solo toca `target_type = PERSONA` o `UBICACION` (las notas del lugar, vista 39,
/// tienen el mismo plazo de 90 días, decisión de Cristian del 03/11): las de una visita o una agenda
/// viven y mueren con su visita o su agenda.
final class NotasBorradasLocalDataSourceDrift {
  NotasBorradasLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  /// Borra las notas de persona y de lugar con `deleted_at` anterior al corte de [ahora] (90 días atrás). Una
  /// nota activa (`deleted_at` nulo) nunca entra, y una restaurada a tiempo tampoco: la restauración
  /// y la limpieza son transacciones de la misma DB, así que se serializan. Devuelve cuántas borró.
  Future<int> purgarVencidas({required DateTime ahora}) {
    final corte = RetencionNotasBorradas.corte(ahora.toUtc()).millisecondsSinceEpoch;
    return (_db.delete(_db.notas)..where(
          (n) =>
              n.targetType.isIn(const [TipoObjetivoNota.persona, TipoObjetivoNota.ubicacion]) &
              n.deletedAt.isNotNull() &
              n.deletedAt.isSmallerThanValue(corte),
        ))
        .go();
  }
}

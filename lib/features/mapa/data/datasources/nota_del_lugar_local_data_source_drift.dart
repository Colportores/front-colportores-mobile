import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/nota_del_lugar.dart';
import '../../domain/services/lector_notas_del_lugar.dart';
import 'notas_table.dart';

/// [LectorNotasDelLugar] sobre la tabla `nota` ([Notas]) de la DB cifrada: las notas de una
/// ubicación son filas con `target_type = UBICACION` y `target_id` = la ubicación.
///
/// **local-only — PII**: la nota no se sincroniza (esquema-datos.md §`nota`). Esta clase solo lee; el
/// alta de notas del lugar llega con la pestaña Notas de la hoja (C·05).
final class NotaDelLugarLocalDataSourceDrift implements LectorNotasDelLugar {
  NotaDelLugarLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  @override
  Stream<NotaDelLugar?> observarMasReciente(String ubicacionId) {
    final consulta = _db.select(_db.notas)
      ..where(
        (n) =>
            n.targetType.equals(TipoObjetivoNota.ubicacion) &
            n.targetId.equals(ubicacionId) &
            n.deletedAt.isNull(),
      )
      // La más nueva primero; a igual instante, la de `id` mayor (UUID v7: crece con el tiempo).
      ..orderBy([(n) => OrderingTerm.desc(n.createdAt), (n) => OrderingTerm.desc(n.id)])
      ..limit(1);
    return consulta.watchSingleOrNull().map(
      (fila) => fila == null
          ? null
          : NotaDelLugar(id: fila.id, texto: fila.texto, creadaEl: fila.createdAt),
    );
  }
}

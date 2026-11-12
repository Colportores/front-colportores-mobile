import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/instante.dart';
import '../../../mapa/data/datasources/notas_table.dart';
import '../../domain/repositories/borrador_de_nota_de_entrevista.dart';

/// [BorradorDeNotaDeEntrevista] sobre la tabla `nota` de la DB local cifrada (local-only: no entra al
/// sync). El borrador es **ya** la fila de la nota de la visita (`target_type = VISITA`, `target_id` =
/// la visita que se va a guardar, mismo `id` que la nota final): al terminar, la visita la reemplaza
/// con el texto definitivo. El texto es dato personal: nunca va a un log.
final class BorradorDeNotaDeEntrevistaDrift implements BorradorDeNotaDeEntrevista {
  BorradorDeNotaDeEntrevistaDrift(this._db);

  final AppDatabase _db;

  @override
  Future<String> leer(String notaId) async {
    final fila = await (_db.select(
      _db.notas,
    )..where((n) => n.id.equals(notaId) & n.deletedAt.isNull())).getSingleOrNull();
    return fila?.texto ?? '';
  }

  @override
  Future<void> guardar({
    required String notaId,
    required String visitaId,
    required String colportorId,
    required String texto,
    required DateTime ahora,
  }) async {
    if (texto.trim().isEmpty) return borrar(notaId);
    final instante = instanteMs(ahora);
    await _db
        .into(_db.notas)
        .insertOnConflictUpdate(
          NotasCompanion.insert(
            id: notaId,
            targetType: TipoObjetivoNota.visita,
            targetId: visitaId,
            texto: texto,
            createdAt: instante,
            updatedAt: instante,
            createdBy: Value(colportorId),
          ),
        );
  }

  @override
  Future<void> borrar(String notaId) =>
      (_db.delete(_db.notas)..where((n) => n.id.equals(notaId))).go();
}

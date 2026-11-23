import '../../../../core/database/app_database.dart';
import '../../../mapa/data/datasources/uniones_locales_table.dart';
import '../../domain/repositories/uniones_deshechas_repository.dart';

/// [UnionesDeshechasRepository] sobre `ubicacion_union_local` de la DB local: la señal es la unión
/// en estado `DESHECHA`, no la operación del trabajo (un «marcar como duplicado» rechazado todavía
/// sin deshacer sí se puede reintentar).
final class UnionesDeshechasRepositoryImpl implements UnionesDeshechasRepository {
  const UnionesDeshechasRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<Set<String>> trabajos() async {
    final uniones = _db.unionesLocales;
    final filas = await (_db.select(
      uniones,
    )..where((u) => u.estado.equals(EstadoUnionLocal.deshecha))).get();
    return {for (final u in filas) u.trabajoId};
  }
}

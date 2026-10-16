import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import 'sesion_usuario_table.dart';

part 'sesion_usuario_local_data_source.g.dart';

/// Copia local del nombre del usuario en la tabla `sesion_usuario` de la DB cifrada (#243).
@DriftAccessor(tables: [SesionUsuarios])
final class SesionUsuarioLocalDataSource extends DatabaseAccessor<AppDatabase>
    with _$SesionUsuarioLocalDataSourceMixin {
  SesionUsuarioLocalDataSource(super.attachedDatabase);

  /// El nombre guardado de [usuarioId], o `null` si no hay (o es de otro usuario).
  Future<String?> leer(String usuarioId) async {
    final fila = await (select(
      sesionUsuarios,
    )..where((s) => s.usuarioId.equals(usuarioId))).getSingleOrNull();
    return fila?.nombre;
  }

  /// Guarda (o reemplaza) el nombre de [usuarioId]. No hay más de una fila por usuario.
  Future<void> guardar(String usuarioId, String nombre) => into(
    sesionUsuarios,
  ).insertOnConflictUpdate(SesionUsuariosCompanion.insert(usuarioId: usuarioId, nombre: nombre));

  /// Borra todo lo guardado: al cerrar sesión no queda el nombre de nadie en el teléfono.
  Future<void> borrar() => delete(sesionUsuarios).go();
}

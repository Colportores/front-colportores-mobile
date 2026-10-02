import 'package:drift/drift.dart';

/// Tabla `sesion_usuario` de la DB local cifrada: la copia del nombre del usuario que dejó el
/// ingreso (#243), para el saludo «Buen trabajo, NOMBRE» sin conexión.
///
/// **Solo local**: no existe en el cloud ni entra al sync (el nombre ya está en `usuario`). Una
/// fila por usuario que entró en este teléfono; se borra al cerrar sesión, y se va entera con el
/// archivo al borrar los datos locales. Es dato personal: la DB está cifrada y el nombre nunca se
/// loguea.
@DataClassName('SesionUsuarioFila')
class SesionUsuarios extends Table {
  @override
  String get tableName => 'sesion_usuario';

  /// UUID del usuario (`auth.users.id`).
  TextColumn get usuarioId => text().named('usuario_id')();

  TextColumn get nombre => text()();

  @override
  Set<Column<Object>> get primaryKey => {usuarioId};
}

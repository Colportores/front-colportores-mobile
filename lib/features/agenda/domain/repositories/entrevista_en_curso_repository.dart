import '../entities/entrevista_en_curso.dart';

/// Dónde se guarda la entrevista en curso de cada colportora en el teléfono, para que sobreviva a
/// cerrar la app. Una por colportora (un teléfono compartido no mezcla entrevistas).
///
/// Las operaciones **lanzan** si el almacén falla: quien las llama las traduce a un `Failure`.
abstract interface class EntrevistaEnCursoRepository {
  /// La entrevista en curso de [colportorId], o `null` si no tiene. Un registro que no se puede
  /// leer cuenta como «ninguna» (nunca se inventa una).
  Future<EntrevistaEnCurso?> leer(String colportorId);

  /// Guarda [entrevista] como la en curso de su colportora, reemplazando la que hubiera.
  Future<void> guardar(EntrevistaEnCurso entrevista);

  /// Borra la entrevista en curso de [colportorId]. Con [idVisita], solo si es esa: así una
  /// entrevista nueva no se borra por cerrar una vieja.
  Future<void> borrar(String colportorId, {String? idVisita});
}

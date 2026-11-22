import '../../domain/entities/entrevista_en_curso.dart';
import '../../domain/repositories/entrevista_en_curso_repository.dart';

/// [EntrevistaEnCursoRepository] en memoria: para los tests y para los widgets que no cablean el
/// almacén. **No sobrevive a cerrar la app.**
final class EntrevistaEnCursoEnMemoria implements EntrevistaEnCursoRepository {
  final Map<String, EntrevistaEnCurso> guardadas = {};

  @override
  Future<EntrevistaEnCurso?> leer(String colportorId) async => guardadas[colportorId];

  @override
  Future<void> guardar(EntrevistaEnCurso entrevista) async {
    guardadas[entrevista.colportorId] = entrevista;
  }

  @override
  Future<void> borrar(String colportorId, {String? idVisita}) async {
    final actual = guardadas[colportorId];
    if (actual == null) return;
    if (idVisita != null && actual.ids.visita != idVisita) return;
    guardadas.remove(colportorId);
  }
}

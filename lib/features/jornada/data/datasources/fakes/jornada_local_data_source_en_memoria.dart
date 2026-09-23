import '../../models/jornada_model.dart';
import '../jornada_local_data_source.dart';

/// Jornadas en memoria, con las mismas reglas que tiene que cumplir la tabla real.
///
/// Sirve para desarrollar la UI (#71) y para los tests del repositorio sin abrir una DB; la
/// implementación de producción es `JornadaLocalDataSourceDrift`. **No es código de producción**:
/// no persiste nada entre ejecuciones.
final class JornadaLocalDataSourceEnMemoria implements JornadaLocalDataSource {
  JornadaLocalDataSourceEnMemoria({Iterable<JornadaModel> iniciales = const []}) {
    for (final jornada in iniciales) {
      _jornadas[jornada.id] = jornada;
    }
  }

  final Map<String, JornadaModel> _jornadas = {};

  /// Todas las jornadas guardadas, en orden de inserción.
  List<JornadaModel> get jornadas => List.unmodifiable(_jornadas.values);

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) async => _activa(colportorId);

  @override
  Future<void> insertar(JornadaModel jornada) async {
    // Sin `await` entre la comprobación y la escritura: en un solo isolate eso ya es atómico,
    // que es lo que la implementación sobre Drift resuelve con una transacción.
    if (_activa(jornada.colportorId) != null) throw const JornadaActivaExistenteException();
    if (_jornadas.containsKey(jornada.id)) {
      throw StateError('ya existe una jornada con id ${jornada.id}');
    }
    _jornadas[jornada.id] = jornada;
  }

  JornadaModel? _activa(String colportorId) {
    for (final jornada in _jornadas.values) {
      if (jornada.colportorId == colportorId && jornada.estaAbierta) return jornada;
    }
    return null;
  }
}

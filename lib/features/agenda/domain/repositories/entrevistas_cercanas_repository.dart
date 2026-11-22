import '../entities/entrevista_cercana.dart';

/// La distancia de «a menos de 300 m» (vista 39, R·02; regla R2 del mapa de decisiones).
const radioDeEntrevistasCercanasMetros = 300.0;

/// Lee del teléfono las entrevistas que el colportor ya tiene agendadas cerca de una casa, para
/// sugerir la fecha de la siguiente (vista 39, R·02). Solo del teléfono: funciona sin conexión.
abstract interface class EntrevistasCercanasRepository {
  /// Las agendas `ENTREVISTA` y `PROGRAMADA` de [colportorId], sin baja, con fecha desde [desde]
  /// (incluida), cuya casa queda a **menos de** [radioMetros] de la del espacio [espacioId] (la casa
  /// misma cuenta: está a 0 m). No trae las de una casa o un depto dados de baja. Sin la casa de
  /// [espacioId] en el teléfono, o sin coordenadas utilizables, devuelve la lista vacía.
  Future<List<EntrevistaCercana>> leer({
    required String colportorId,
    required String espacioId,
    required DateTime desde,
    double radioMetros = radioDeEntrevistasCercanasMetros,
  });
}

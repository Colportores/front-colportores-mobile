import '../../../mapa/domain/repositories/ubicacion_alternativa_repository.dart';
import '../entities/destino_de_cobranza.dart';

/// HU-VIS-006 — Dónde proponer la cobranza de [personaId] en [espacioId]: la ubicación alternativa si
/// la tiene y sigue activa (la UI la sugiere por defecto), la del espacio si no tiene, o una
/// advertencia si la alternativa se dio de baja. Solo lee del teléfono y se actualiza sola cuando
/// cambia la alternativa; un error de lectura sale por el `Stream`.
final class ObservarDestinoDeCobranzaUseCase {
  ObservarDestinoDeCobranzaUseCase(this._repository);

  final UbicacionAlternativaRepository _repository;

  Stream<DestinoDeCobranza> call({required String personaId, required String espacioId}) =>
      _repository.observar(personaId: personaId, espacioId: espacioId).map(DestinoDeCobranza.de);
}

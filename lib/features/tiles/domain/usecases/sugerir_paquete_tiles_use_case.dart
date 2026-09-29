import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/paquete_tiles.dart';
import '../repositories/paquetes_tiles_repository.dart';

/// HU-SYNC-010 + HU-CAM-005 — al cambiar de ciudad o de zona, qué paquete sugerir descargar para
/// el lugar nuevo.
///
/// `Right(null)` si ya hay un paquete descargado que lo cubre. Si no, el del catálogo de nivel más
/// chico que lo cubra: zona (el default sugerido por la HU), después ciudad y después
/// departamento. Uruguay completo (~500 MB–1 GB) no se sugiere solo: lo elige el colportor en
/// "Mapas offline" (para confirmar en #189). Quien detecta el cambio de lugar (la reasignación
/// llega por sync) llama a este caso de uso con el lugar nuevo.
final class SugerirPaqueteTilesUseCase implements UseCase<PaqueteTiles?, AmbitoTrabajo> {
  SugerirPaqueteTilesUseCase(this._repository);

  final PaquetesTilesRepository _repository;

  @override
  Future<Either<Failure, PaqueteTiles?>> call(AmbitoTrabajo ambito) async {
    final descargados = (await _repository.descargados()).getOrElse(() => const []);
    if (elegirPaqueteOffline(descargados, ambito) != null) return const Right(null);
    final catalogo = await _repository.catalogo();
    return catalogo.map((paquetes) => _sugerido(paquetes, ambito));
  }

  static PaqueteTiles? _sugerido(List<PaqueteTiles> catalogo, AmbitoTrabajo ambito) {
    PaqueteTiles? elegido;
    for (final paquete in catalogo) {
      if (paquete.nivel == NivelCobertura.uruguay || !paquete.cubre(ambito)) continue;
      if (elegido == null || paquete.nivel.index < elegido.nivel.index) elegido = paquete;
    }
    return elegido;
  }
}

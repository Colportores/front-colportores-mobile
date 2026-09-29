import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/cobertura_tiles.dart';
import '../entities/paquete_tiles.dart';
import '../repositories/paquetes_tiles_repository.dart';

/// HU-SYNC-010 — las cuatro opciones de cobertura (zona, ciudad, departamento, Uruguay) para el
/// lugar donde trabaja el colportor, con lo que ya tiene descargado.
///
/// Sin catálogo (sin red) igual devuelve `Right`: las opciones quedan sin paquete del catálogo,
/// con los descargados, y [CoberturaTiles.falloCatalogo] dice por qué. Solo si no se pueden leer
/// los descargados devuelve `Left`.
final class ListarCoberturaTilesUseCase implements UseCase<CoberturaTiles, AmbitoTrabajo> {
  ListarCoberturaTilesUseCase(this._repository);

  final PaquetesTilesRepository _repository;

  @override
  Future<Either<Failure, CoberturaTiles>> call(AmbitoTrabajo ambito) async {
    final respuesta = await _repository.catalogo();
    final catalogo = respuesta.getOrElse(() => const []);
    final falloCatalogo = respuesta.fold<Failure?>((failure) => failure, (_) => null);
    final leidos = await _repository.descargados();
    return leidos.map((descargados) => _armar(ambito, catalogo, descargados, falloCatalogo));
  }

  static CoberturaTiles _armar(
    AmbitoTrabajo ambito,
    List<PaqueteTiles> catalogo,
    List<PaqueteDescargado> descargados,
    Failure? falloCatalogo,
  ) {
    final enOpciones = <String>{};
    final opciones = <OpcionCobertura>[];
    for (final nivel in NivelCobertura.values) {
      bool sirve(PaqueteTiles paquete) => paquete.nivel == nivel && paquete.cubre(ambito);
      final paquete = catalogo.where(sirve).firstOrNull;
      final descargado = descargados.where((d) => sirve(d.paquete)).firstOrNull;
      if (descargado != null) enOpciones.add(descargado.id);
      opciones.add(OpcionCobertura(nivel: nivel, paquete: paquete, descargado: descargado));
    }
    final otros = descargados.where((d) => !enOpciones.contains(d.id)).toList();
    return CoberturaTiles(
      opciones: opciones,
      otrosDescargados: otros,
      falloCatalogo: falloCatalogo,
    );
  }
}

import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/paquete_tiles.dart';

/// Los paquetes PMTiles: el catálogo para descargar y los que ya están en el teléfono
/// (HU-SYNC-010, ADR-011).
///
/// Es lo que consume el mapa (HU-UBI-003) para priorizar el paquete offline sobre el online: con
/// [observarDescargados] y `elegirPaqueteOffline` sabe si hay uno para el lugar y su archivo.
abstract interface class PaquetesTilesRepository {
  /// Los paquetes que se pueden descargar. Necesita red.
  Future<Either<Failure, List<PaqueteTiles>>> catalogo();

  /// Los paquetes descargados y validados cuyo archivo sigue en el teléfono.
  Future<Either<Failure, List<PaqueteDescargado>>> descargados();

  /// [descargados] como flujo: emite al suscribirse y cada vez que se registra o se quita uno.
  Stream<List<PaqueteDescargado>> observarDescargados();

  /// Anota un paquete ya descargado y validado; reemplaza al anterior con el mismo id.
  Future<Either<Failure, Unit>> registrar(PaqueteDescargado descargado);

  /// Deja de anotar el paquete [paqueteId]; si no estaba, no hace nada.
  Future<Either<Failure, Unit>> quitar(String paqueteId);
}

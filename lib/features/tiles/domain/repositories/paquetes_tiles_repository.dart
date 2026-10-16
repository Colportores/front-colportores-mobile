import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/descarga_pendiente.dart';
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

  /// Anota un paquete ya descargado y validado; reemplaza al anterior con el mismo id (y borra los
  /// archivos de la versión anterior, que ya no se usan).
  Future<Either<Failure, Unit>> registrar(PaqueteDescargado descargado);

  /// Deja de anotar el paquete [paqueteId]; si no estaba, no hace nada.
  Future<Either<Failure, Unit>> quitar(String paqueteId);

  /// Las descargas que el colportor pidió y todavía no terminaron, vigentes (las de más de
  /// [DescargaPendiente.vigencia] días no se informan): lo que `DescargadorPaquetesTiles` retoma al
  /// arrancar la app (HU-SYNC-010, «La descarga sigue después de cerrar la app»).
  Future<Either<Failure, List<DescargaPendiente>>> descargasPendientes();

  /// Anota una descarga pendiente; reemplaza a la anterior con el mismo id.
  Future<Either<Failure, Unit>> anotarDescargaPendiente(DescargaPendiente pendiente);

  /// Deja de anotar la descarga pendiente de [paqueteId] (terminó, falló, la eliminaron); si no
  /// estaba, no hace nada.
  Future<Either<Failure, Unit>> olvidarDescargaPendiente(String paqueteId);

  /// Pone en orden lo que hay en el teléfono con lo que está anotado (se llama una vez al arrancar
  /// la app): un paquete anotado al que le falta un archivo, o cuyo archivo no pesa lo que
  /// tiene que pesar o no pasa el checksum, se trata como no descargado y se saca del registro;
  /// y los archivos que no son de ningún paquete anotado se borran (un `.pmtiles` huérfano, un
  /// `.part` abandonado). Las descargas pendientes vencidas (7 días), o de un paquete que ya está
  /// descargado con esa versión, se olvidan; el `.part` de una vigente se conserva.
  Future<Either<Failure, Unit>> reconciliar();
}

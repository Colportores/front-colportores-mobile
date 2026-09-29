import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/zona_ubicable.dart';

/// Las zonas del mapa que el teléfono tiene replicadas del canal de catálogo (`zona`,
/// `campania_ciudad`; contrato-sync-engine §2, política `pull`). La app nunca las escribe.
abstract interface class ZonaRepository {
  /// Las zonas vivas de la ciudad [ciudadId]: la zona y su `campania_ciudad` sin baja, de cualquier
  /// campaña que el teléfono tenga. Una zona cuya forma no se puede leer no se devuelve.
  Future<Either<Failure, List<ZonaUbicable>>> vivasDeCiudad(String ciudadId);
}

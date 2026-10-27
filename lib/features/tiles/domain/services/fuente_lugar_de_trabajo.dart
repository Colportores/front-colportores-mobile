import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/lugar_de_trabajo.dart';

/// Puerto: dónde trabaja el colportor (su zona asignada y su ciudad), para ofrecerle los mapas que
/// le sirven (HU-SYNC-010) y sugerirle el de una zona nueva (HU-CAM-005).
///
/// La fuente real sale del teléfono, sin red: la réplica local de las zonas y las ciudades de su
/// campaña (front-colportores-mobile#274). Una `Left` quiere decir «no se pudo leer»; una zona
/// `null` en el [LugarDeTrabajo], «se leyó y no tiene zona asignada». Una fuente que no sabe
/// **nunca** contesta lo segundo.
abstract interface class FuenteLugarDeTrabajo {
  Future<Either<Failure, LugarDeTrabajo>> leer();
}

/// Mientras no exista la réplica local (#274) no hay de dónde leerlo: contesta que no sabe. «Mapas
/// offline» sigue mostrando lo que ya está descargado y deja borrarlo. **No es la regla de la HU**:
/// se reemplaza por la lectura de la réplica cuando exista.
final class FuenteLugarDeTrabajoSinFuente implements FuenteLugarDeTrabajo {
  const FuenteLugarDeTrabajoSinFuente();

  @override
  Future<Either<Failure, LugarDeTrabajo>> leer() async =>
      const Left(FailureLugarDeTrabajoNoDisponible());
}

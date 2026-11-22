import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/ciudad_consultable.dart';

/// Puerto: las ciudades cuyos precios puede consultar [colportorId] (vista 26) y la de su zona.
///
/// La fuente real sale del teléfono, sin red: la réplica local de `ciudad`, `campania`,
/// `campania_ciudad` y `campania_colportor` (front-colportores-mobile#274, junto al pull de
/// catálogos). Una `Left` quiere decir «no se pudo leer»; un [ContextoDeCiudades] sin ciudades, «se
/// leyó y no tiene campañas en curso». Una fuente que no sabe **nunca** contesta lo segundo.
abstract interface class FuenteDeCiudadesParaPrecios {
  Future<Either<Failure, ContextoDeCiudades>> leer(String colportorId);
}

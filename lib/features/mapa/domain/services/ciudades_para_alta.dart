import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../value_objects/coordenadas.dart';

/// Una ciudad del catálogo del Admin (HU-UBI-001: `ciudad_id` es una FK a ese catálogo).
final class CiudadCatalogo extends Equatable {
  const CiudadCatalogo({required this.id, required this.nombre});

  final String id;
  final String nombre;

  @override
  List<Object?> get props => [id, nombre];
}

/// Qué ciudad del catálogo corresponde a un punto (HU-UBI-001: «la ciudad detectada por las
/// coords»).
sealed class DeteccionCiudad extends Equatable {
  const DeteccionCiudad();
}

/// El punto cae en una sola ciudad del catálogo.
final class CiudadDetectada extends DeteccionCiudad {
  const CiudadDetectada(this.ciudad);

  final CiudadCatalogo ciudad;

  @override
  List<Object?> get props => [ciudad];
}

/// El punto está cerca del límite de dos ciudades o más: HU-UBI-001 pide preguntar al colportor y
/// no asignar ninguna.
final class CiudadAmbigua extends DeteccionCiudad {
  const CiudadAmbigua(this.candidatas);

  final List<CiudadCatalogo> candidatas;

  @override
  List<Object?> get props => [candidatas];
}

/// El catálogo no incluye la ciudad del punto (HU-UBI-001, «Error - ciudad no en catálogo»).
final class CiudadNoEncontrada extends DeteccionCiudad {
  const CiudadNoEncontrada();

  @override
  List<Object?> get props => const [];
}

/// Puerto: las ciudades que el alta de ubicación necesita (vista 03, «Montevideo detectada»,
/// «de tu zona», «Cambiar»).
///
/// No hay tabla `ciudad` en la DB local ni geometrías de ciudad: la fuente real llega con el
/// catálogo del Admin (HU-ADM) y el BFF (docs-organizacion#22). Hasta entonces no hay
/// implementación de producción (`CiudadesParaAltaSinFuente`).
abstract interface class CiudadesParaAlta {
  /// La ciudad que contiene [punto].
  Future<Either<Failure, DeteccionCiudad>> detectar(Coordenadas punto);

  /// Todo el catálogo, para «Cambiar» y «Seleccionar ciudad manualmente».
  Future<Either<Failure, List<CiudadCatalogo>>> todas();

  /// La ciudad de la zona asignada a [colportorId]: lo que se prellena si no hay GPS (vista 03).
  /// `null` si no tiene zona o no se conoce.
  Future<Either<Failure, CiudadCatalogo?>> deMiZona(String colportorId);
}

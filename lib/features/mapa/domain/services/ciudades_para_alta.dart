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

/// De dónde sale la ciudad que se le propone al colportor (vista 03: «detectada», «de tu zona»,
/// «de tu campaña»).
enum OrigenPropuesta {
  /// La ciudad de la zona de sus campañas que contiene el punto.
  detectada,

  /// La ciudad de la zona que tiene asignada.
  deZona,

  /// La única ciudad de su campaña o, con varias, la que tiene el centro más cerca del punto.
  deCampania,
}

/// Qué ciudad se le propone al colportor para una ubicación nueva.
///
/// La ciudad **nunca limita el alta** (decisión de Cristian, 02/10, en front-colportores-mobile#267):
/// la app siempre propone una ciudad de la campaña del colportor, aun sin red, y el colportor la puede
/// cambiar por otra de su campaña. Por eso no hay «no encontrada», «ambigua» ni «pedir el alta de la
/// ciudad». El único caso sin propuesta es una campaña sin ciudades cargadas.
sealed class PropuestaCiudad extends Equatable {
  const PropuestaCiudad();
}

/// La ciudad propuesta y de dónde sale.
final class CiudadPropuesta extends PropuestaCiudad {
  const CiudadPropuesta(this.ciudad, this.origen);

  final CiudadCatalogo ciudad;
  final OrigenPropuesta origen;

  @override
  List<Object?> get props => [ciudad, origen];
}

/// La campaña del colportor todavía no tiene ciudades cargadas: no hay qué proponer ni qué elegir.
final class CampaniaSinCiudades extends PropuestaCiudad {
  const CampaniaSinCiudades();

  @override
  List<Object?> get props => const [];
}

/// Sin punto no se puede elegir entre varias ciudades de la campaña (no hay zona asignada ni
/// distancia que medir). Se vuelve a pedir cuando el colportor marque el punto.
final class FaltaElPunto extends PropuestaCiudad {
  const FaltaElPunto();

  @override
  List<Object?> get props => const [];
}

/// Puerto: las ciudades que el alta de ubicación necesita (vista 03, «Montevideo detectada»,
/// «de tu zona», «Cambiar»). Todas son **de la campaña del colportor**.
///
/// La fuente real sale del teléfono, sin red: la réplica local del catálogo de ciudades (el nombre),
/// las campañas del colportor, sus zonas y los centros de las ciudades. Hasta que esa réplica exista
/// no hay implementación de producción (`CiudadesParaAltaSinFuente`).
abstract interface class CiudadesParaAlta {
  /// La ciudad para una ubicación nueva de [colportorId], en este orden:
  /// 1. la de la zona de sus campañas que contiene [punto] ([OrigenPropuesta.detectada]);
  /// 2. la de la zona que tiene asignada ([OrigenPropuesta.deZona]);
  /// 3. la única ciudad de su campaña ([OrigenPropuesta.deCampania]);
  /// 4. la de la campaña con el centro más cerca de [punto] ([OrigenPropuesta.deCampania]).
  ///
  /// Sin [punto] se aplican solo el 2 y el 3: con varias ciudades y sin zona asignada devuelve
  /// [FaltaElPunto].
  Future<Either<Failure, PropuestaCiudad>> proponer({
    required String colportorId,
    Coordenadas? punto,
  });

  /// Las ciudades de la campaña de [colportorId], para «Cambiar». Vacía si la campaña no tiene.
  Future<Either<Failure, List<CiudadCatalogo>>> deMiCampania(String colportorId);
}

import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import 'paquete_tiles.dart';

/// Una de las cuatro opciones de "Mapas offline" (HU-SYNC-010): el paquete de ese nivel que cubre
/// el lugar del colportor y, si lo tiene, el que ya descargó.
final class OpcionCobertura extends Equatable {
  const OpcionCobertura({required this.nivel, this.paquete, this.descargado});

  final NivelCobertura nivel;

  /// El paquete del catálogo; `null` si el catálogo no tiene uno para el lugar o no se pudo leer.
  final PaqueteTiles? paquete;

  /// El paquete de este nivel que ya está en el teléfono; `null` si no hay.
  final PaqueteDescargado? descargado;

  /// El catálogo tiene otra versión (otro checksum) que la descargada.
  bool get hayActualizacion {
    final nuevo = paquete;
    final actual = descargado;
    return nuevo != null && actual != null && nuevo.checksum != actual.paquete.checksum;
  }

  @override
  List<Object?> get props => [nivel, paquete, descargado];
}

/// Lo que muestra "Mapas offline": una opción por nivel para el lugar del colportor y los
/// paquetes descargados que no son de ninguna (p. ej. de la ciudad anterior), para poder
/// eliminarlos y liberar espacio.
final class CoberturaTiles extends Equatable {
  const CoberturaTiles({
    required this.opciones,
    required this.otrosDescargados,
    this.falloCatalogo,
  });

  /// Una por nivel, en el orden de [NivelCobertura] (zona primero: el default sugerido).
  final List<OpcionCobertura> opciones;
  final List<PaqueteDescargado> otrosDescargados;

  /// Por qué no se pudo leer el catálogo (sin red, por ejemplo); `null` si se leyó. Sin catálogo
  /// se siguen viendo los descargados.
  final Failure? falloCatalogo;

  @override
  List<Object?> get props => [opciones, otrosDescargados, falloCatalogo];
}

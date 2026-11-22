import 'package:equatable/equatable.dart';

import '../../../catalogo/domain/entities/ciudad_consultable.dart';

/// Con qué precios se vende a un cliente (decisión P4 de #158): los de la **ciudad de su casa**, en la
/// campaña en curso. No se usa el GPS.
sealed class PreciosDeLaVenta extends Equatable {
  const PreciosDeLaVenta();
}

/// Hay una campaña en curso en la ciudad de la casa: se vende con sus precios.
final class PreciosVigentes extends PreciosDeLaVenta {
  const PreciosVigentes(this.ciudad);

  /// Su `campaniaCiudadId` es la clave con la que se lee el catálogo local.
  final CiudadConsultable ciudad;

  @override
  List<Object?> get props => [ciudad];
}

/// La campaña de la ciudad de la casa terminó (o no hay ninguna): no se vende hasta que haya otra en
/// curso (27A·10). [terminada] es la última, si se sabe.
final class SinCampaniaVigente extends PreciosDeLaVenta {
  const SinCampaniaVigente({this.terminada});

  final CampaniaTerminada? terminada;

  @override
  List<Object?> get props => [terminada];
}

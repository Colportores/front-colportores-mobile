import 'package:equatable/equatable.dart';

import 'coordenadas.dart';

/// De dónde salieron las coordenadas de un alta (HU-UBI-001: `coords_source`, "para auditoría").
enum OrigenCoordenadas {
  /// Lectura del GPS del teléfono.
  gps,

  /// Marcador puesto a mano sobre el mapa ("Marcar en el mapa").
  manual,
}

/// Una posición que devolvió el GPS, con la precisión que reporta el sistema operativo.
final class LecturaGps extends Equatable {
  const LecturaGps({required this.coordenadas, required this.precisionMetros});

  final Coordenadas coordenadas;

  /// Radio de incertidumbre en metros que reporta el SO (68 % de confianza en Android e iOS).
  final double precisionMetros;

  @override
  List<Object?> get props => [coordenadas, precisionMetros];
}

/// El punto elegido para un alta: una lectura del GPS o un marcador puesto a mano.
final class PuntoCapturado extends Equatable {
  /// Lectura del GPS: lleva su precisión, y si pasa de [umbralPrecisionMetros] el alta pide
  /// confirmación.
  PuntoCapturado.gps(LecturaGps lectura)
    : coordenadas = lectura.coordenadas,
      origen = OrigenCoordenadas.gps,
      precisionMetros = lectura.precisionMetros;

  /// Marcador manual: no tiene precisión que advertir, el colportor eligió el punto.
  const PuntoCapturado.manual(this.coordenadas)
    : origen = OrigenCoordenadas.manual,
      precisionMetros = null;

  /// HU-UBI-001: "si la precisión reportada por el SO es > 50m, advertir antes de aceptar".
  static const umbralPrecisionMetros = 50.0;

  final Coordenadas coordenadas;
  final OrigenCoordenadas origen;

  /// Solo para [OrigenCoordenadas.gps].
  final double? precisionMetros;

  /// `true` si es una lectura del GPS con precisión peor que [umbralPrecisionMetros].
  bool get esImpreciso {
    final precision = precisionMetros;
    return precision != null && precision > umbralPrecisionMetros;
  }

  @override
  List<Object?> get props => [coordenadas, origen, precisionMetros];
}

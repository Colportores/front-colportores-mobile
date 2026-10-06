import 'package:equatable/equatable.dart';

import '../value_objects/coordenadas.dart';

/// La calle y el número que el mapa conoce de un punto (vista 03: «Del mapa»).
final class DireccionDelPunto extends Equatable {
  const DireccionDelPunto({this.calle, this.numero});

  final String? calle;
  final String? numero;

  /// `true` si el mapa no sabe ni la calle ni el número.
  bool get estaVacia => (calle ?? '').trim().isEmpty && (numero ?? '').trim().isEmpty;

  @override
  List<Object?> get props => [calle, numero];
}

/// Puerto: la dirección de un punto (geocodificación inversa, ADR-011: Photon offline y, si no
/// está, Nominatim; vista 03 «Calle y número se completan con la dirección del punto»).
///
/// Nunca lanza. Devuelve `null` cuando no se pudo saber: sin red y sin índice offline (la vista 03
/// lo dice: «calle y número quedan vacíos para escribirlos, y se registra igual con las
/// coordenadas»), sin calle en ese punto, o una respuesta ilegible.
abstract interface class GeocodificadorInverso {
  Future<DireccionDelPunto?> direccionDe(Coordenadas punto);
}

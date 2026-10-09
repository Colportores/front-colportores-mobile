import 'package:equatable/equatable.dart';

/// Lo que la app le dice al colportor cuando el pull trae un cambio de su zona (HU-CAM-006, #251,
/// decisión de Cristian, 30/09, en front-coordinadores-web#20). Sin push: se muestra al abrir la
/// app o cuando termina un pull con la app abierta.
sealed class AvisoZona extends Equatable {
  const AvisoZona({required this.inscripcionId, required this.campaniaNombre});

  /// La inscripción (`campania_colportor.id`) a la que se refiere el aviso: hay a lo sumo uno por
  /// inscripción, siempre el último cambio.
  final String inscripcionId;

  final String campaniaNombre;

  /// La zona que el colportor tiene ahora en [inscripcionId], o `null` si quedó sin zona. Es lo que
  /// se guarda como «ya avisada» al cerrar el aviso.
  String? get zonaId;
}

/// «Te asignaron la zona `zona` en `campaña`.»: le asignaron una zona o le cambiaron la que tenía.
final class ZonaAsignada extends AvisoZona {
  const ZonaAsignada({
    required super.inscripcionId,
    required super.campaniaNombre,
    required this.zonaId,
    required this.zonaNombre,
  });

  @override
  final String zonaId;

  final String zonaNombre;

  @override
  List<Object?> get props => [inscripcionId, campaniaNombre, zonaId, zonaNombre];
}

/// «Ya no tenés zona en `campaña`.»: sigue inscripto y quedó sin zona (por ejemplo, con «Quitar»).
final class ZonaQuitada extends AvisoZona {
  const ZonaQuitada({required super.inscripcionId, required super.campaniaNombre});

  @override
  String? get zonaId => null;

  @override
  List<Object?> get props => [inscripcionId, campaniaNombre];
}

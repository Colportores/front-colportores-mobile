import 'package:equatable/equatable.dart';

/// Una inscripción propia del colportor (`campania_colportor`, réplica del pull de catálogos) con
/// los nombres que hacen falta para avisarle de su zona: el de la campaña y el de la zona.
///
/// Es lo que lee el aviso de «Te asignaron la zona…» (HU-CAM-006, #251). El teléfono nunca la
/// escribe: la baja el pull.
class InscripcionConZona extends Equatable {
  const InscripcionConZona({
    required this.id,
    required this.campaniaId,
    required this.campaniaNombre,
    this.zonaId,
    this.zonaNombre,
    this.dadaDeBaja = false,
  });

  /// `campania_colportor.id`: lo que identifica a la inscripción entre un pull y el siguiente.
  final String id;

  final String campaniaId;

  /// Nombre de la campaña, tal cual la cargó el coordinador.
  final String campaniaNombre;

  /// La zona asignada, o `null`: el colportor está inscripto pero «sin zona».
  final String? zonaId;

  /// Nombre de la zona [zonaId]. `null` mientras la zona no llegó a la réplica local (el pull baja
  /// la inscripción y el mapa por separado): con [zonaId] y sin nombre, la inscripción todavía no
  /// se puede avisar.
  final String? zonaNombre;

  /// La inscripción llegó con baja (`deleted_at`): lo sacaron de la campaña (HU-CAM-005). Esa baja
  /// también deja la zona en `null`, y **no** se avisa como «ya no tenés zona»: alcanza con la
  /// notificación de remoción (decisión del orquestador, 02/10, en docs-organizacion#33).
  final bool dadaDeBaja;

  @override
  List<Object?> get props => [id, campaniaId, campaniaNombre, zonaId, zonaNombre, dadaDeBaja];
}

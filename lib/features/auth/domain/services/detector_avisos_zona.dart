import 'package:equatable/equatable.dart';

import '../entities/aviso_zona.dart';
import '../entities/inscripcion_con_zona.dart';

/// Qué hay que avisar y qué anotar en silencio después de mirar las inscripciones del teléfono.
final class ResultadoAvisosZona extends Equatable {
  const ResultadoAvisosZona({required this.avisos, required this.silenciosas});

  /// Los avisos para mostrar, a lo sumo uno por inscripción y en el orden de las inscripciones.
  final List<AvisoZona> avisos;

  /// Lo que hay que anotar como «visto» sin avisar nada (inscripciones sin zona que se ven por
  /// primera vez, o que llegaron dadas de baja): inscripción → zona (`null` = sin zona).
  final Map<String, String?> silenciosas;

  @override
  List<Object?> get props => [avisos, silenciosas];
}

/// Decide si la zona de una inscripción cambió desde la última vez que se le avisó al colportor
/// (HU-CAM-006, #251). Es una función de lo que el teléfono tiene replicado y de lo que ya avisó:
/// no depende de cuándo ni cuántas veces llegó el pull, así que dos pulls seguidos con el mismo
/// cambio avisan una sola vez y un cambio que llegó con la app cerrada se avisa al abrirla.
///
/// Reglas, por cada inscripción de [actuales]:
/// - **Con baja** (lo sacaron de la campaña, HU-CAM-005): no se avisa nada, ni «te asignaron» ni «ya
///   no tenés zona»; se anota sin zona (la baja también deja `zona_id` en `null`).
/// - **Con zona y sin su nombre** (la inscripción llegó antes que la zona, o sin nombre de
///   campaña): no se avisa ni se anota; cuando el nombre llegue, la réplica vuelve a emitir.
/// - **Con zona distinta a la ya avisada** —o con zona y nunca vista—: [ZonaAsignada].
/// - **Sin zona, con una zona ya avisada**: [ZonaQuitada].
/// - **Sin zona y nunca vista**: nada que avisar; se anota sin zona, así la primera zona que le
///   asignen es un cambio y se avisa.
/// - Igual a lo ya avisado: nada.
abstract final class DetectorAvisosZona {
  /// [avisadas]: inscripción → la zona de la última vez que se le avisó (`null` = quedó sin zona).
  /// Una inscripción que no está es una que el teléfono nunca vio.
  static ResultadoAvisosZona detectar({
    required Map<String, String?> avisadas,
    required Iterable<InscripcionConZona> actuales,
  }) {
    final avisos = <AvisoZona>[];
    final silenciosas = <String, String?>{};
    for (final inscripcion in actuales) {
      final campania = _nombre(inscripcion.campaniaNombre);
      final conocida = avisadas.containsKey(inscripcion.id);
      final anterior = avisadas[inscripcion.id];

      if (inscripcion.dadaDeBaja) {
        if (!conocida || anterior != null) silenciosas[inscripcion.id] = null;
        continue;
      }
      if (campania == null) continue;

      final zonaId = inscripcion.zonaId;
      if (zonaId == null) {
        if (!conocida) {
          silenciosas[inscripcion.id] = null;
        } else if (anterior != null) {
          avisos.add(ZonaQuitada(inscripcionId: inscripcion.id, campaniaNombre: campania));
        }
        continue;
      }

      final zona = _nombre(inscripcion.zonaNombre);
      if (zona == null) continue;
      if (conocida && anterior == zonaId) continue;
      avisos.add(
        ZonaAsignada(
          inscripcionId: inscripcion.id,
          campaniaNombre: campania,
          zonaId: zonaId,
          zonaNombre: zona,
        ),
      );
    }
    return ResultadoAvisosZona(avisos: avisos, silenciosas: silenciosas);
  }

  /// El nombre sin espacios alrededor, o `null` si no tiene texto.
  static String? _nombre(String? nombre) {
    final limpio = nombre?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }
}

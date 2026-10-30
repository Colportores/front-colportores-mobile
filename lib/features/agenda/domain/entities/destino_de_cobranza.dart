import 'package:equatable/equatable.dart';

import '../../../mapa/domain/entities/estado_ubicacion_alternativa.dart';
import '../services/texto_recordatorio.dart';

/// Dónde se propone cobrar a una persona al agendar una **cobranza** (HU-VIS-006): en la ubicación
/// alternativa si tiene una activa (HU-UBI-013), en la del espacio si no, o ninguna de las dos hasta
/// que se actualice la alternativa.
///
/// Se arma a partir de [EstadoUbicacionAlternativa] y no guarda ningún dato de la persona: la pantalla
/// que lo dibuje (la vista 22, que todavía no está en `disenio-vistas/`) pone el nombre.
sealed class DestinoDeCobranza extends Equatable {
  const DestinoDeCobranza();

  factory DestinoDeCobranza.de(EstadoUbicacionAlternativa estado) => switch (estado) {
    SinUbicacionAlternativa() => const CobranzaEnLaUbicacionDelEspacio(),
    UbicacionAlternativaVigente(:final ubicacion) => CobranzaEnLaAlternativa(
      ubicacionId: ubicacion.id,
      direccionDelAviso: TextoRecordatorio.direccionDe(ubicacion.calle, ubicacion.numero),
    ),
    UbicacionAlternativaDeBaja(:final ubicacionId) ||
    UbicacionAlternativaFaltante(:final ubicacionId) => CobranzaConAlternativaNoUsable(ubicacionId),
  };

  /// Qué guardar en `agenda.ubicacion_alt_id`: el id de la alternativa, o `null` si se cobra donde
  /// está el espacio (o si la alternativa no sirve y no hay nada que guardar).
  String? get ubicacionAltId => null;

  /// La dirección que lleva el recordatorio (HU-NOT-002) cuando se cobra en la alternativa. Vacía
  /// si se cobra en la del espacio: esa la conoce quien agenda (la de la casa).
  String get direccionDelAviso => '';

  /// Hay una alternativa guardada que no se puede usar: avisar «La ubicación alternativa ya no está
  /// activa. Elegí otra o actualizá.» antes de agendar.
  bool get advierteQueNoSirve => false;
}

/// Sin alternativa: la cobranza va a la ubicación del espacio.
final class CobranzaEnLaUbicacionDelEspacio extends DestinoDeCobranza {
  const CobranzaEnLaUbicacionDelEspacio();

  @override
  List<Object?> get props => const [];
}

/// La cobranza se propone en la ubicación alternativa [ubicacionId] (activa).
final class CobranzaEnLaAlternativa extends DestinoDeCobranza {
  const CobranzaEnLaAlternativa({required this.ubicacionId, required this.direccionDelAviso});

  final String ubicacionId;

  @override
  final String direccionDelAviso;

  @override
  String get ubicacionAltId => ubicacionId;

  @override
  List<Object?> get props => [ubicacionId, direccionDelAviso];
}

/// La persona tiene una alternativa ([ubicacionId]) dada de baja o ausente del teléfono: no se
/// propone ni se guarda, y se advierte (HU-VIS-006, «Edge - alternativa dada de baja»).
final class CobranzaConAlternativaNoUsable extends DestinoDeCobranza {
  const CobranzaConAlternativaNoUsable(this.ubicacionId);

  final String ubicacionId;

  @override
  bool get advierteQueNoSirve => true;

  @override
  List<Object?> get props => [ubicacionId];
}

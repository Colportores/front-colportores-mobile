import 'package:equatable/equatable.dart';

import 'ubicacion.dart';

/// Dónde se le cobra a una persona en un espacio, según su `espacio_persona.ubicacion_cobranza_alt_id`
/// (HU-UBI-013): la ubicación alternativa, la que ya no sirve o ninguna (se cobra donde vive).
sealed class EstadoUbicacionAlternativa extends Equatable {
  const EstadoUbicacionAlternativa();

  /// La ubicación que HU-VIS propone como destino de una cobranza, o `null` si no hay ninguna que
  /// sugerir y se vuelve a la del espacio. Una alternativa dada de baja o que falta **no se sugiere**.
  Ubicacion? get sugerida => null;

  /// Hay una referencia guardada pero no se puede usar: la pantalla avisa «Ubicación alternativa dada
  /// de baja» y pide actualizarla antes de agendar la cobranza.
  bool get requiereActualizar => false;
}

/// No tiene alternativa: la cobranza va a la ubicación del espacio.
final class SinUbicacionAlternativa extends EstadoUbicacionAlternativa {
  const SinUbicacionAlternativa();

  @override
  List<Object?> get props => const [];
}

/// Tiene [ubicacion] activa como alternativa: es la que se sugiere al agendar.
final class UbicacionAlternativaVigente extends EstadoUbicacionAlternativa {
  const UbicacionAlternativaVigente(this.ubicacion);

  final Ubicacion ubicacion;

  @override
  Ubicacion get sugerida => ubicacion;

  @override
  List<Object?> get props => [ubicacion];
}

/// La alternativa [ubicacionId] se dio de baja después de elegirla. No se sugiere.
final class UbicacionAlternativaDeBaja extends EstadoUbicacionAlternativa {
  const UbicacionAlternativaDeBaja(this.ubicacionId);

  final String ubicacionId;

  @override
  bool get requiereActualizar => true;

  @override
  List<Object?> get props => [ubicacionId];
}

/// La alternativa [ubicacionId] no está en el teléfono (el pull no garantiza el orden, o se recuperó
/// la cuenta sin copia): no se la puede mostrar ni sugerir, y tampoco se afirma que esté de baja.
final class UbicacionAlternativaFaltante extends EstadoUbicacionAlternativa {
  const UbicacionAlternativaFaltante(this.ubicacionId);

  final String ubicacionId;

  @override
  bool get requiereActualizar => true;

  @override
  List<Object?> get props => [ubicacionId];
}

import '../domain/entities/motivo_rechazo_agenda.dart';

/// Los textos de agendar una cobranza en la ubicación alternativa (HU-VIS-006). Son los de la HU, tal
/// cual; la vista 22 que los dibuja todavía no está en `disenio-vistas/`, así que ninguna pantalla los
/// usa aún.
abstract final class TextosCobranzaAlternativa {
  /// Escenario «Agendar cobranza alternativa»: confirma el destino, p. ej. «Ubicación B (alternativa
  /// de María)». Lleva el nombre de la persona: se arma al dibujarlo y no se guarda ni se loguea.
  static String destino({required String ubicacion, required String persona}) =>
      '$ubicacion (alternativa de $persona)';

  /// Escenario «Edge - alternativa dada de baja».
  static final alternativaInactiva = MotivoRechazoAgenda.alternativaInactiva.mensaje;

  /// Regla de negocio: el indicador del marcador de la alternativa en el mapa.
  static const indicadorEnElMapa = 'Cobranza pendiente proveniente de otra ubicación';
}

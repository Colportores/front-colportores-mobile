import 'dart:typed_data';

/// Cómo terminó el intento de conseguir la foto del ticket.
sealed class ResultadoDeCaptura {
  const ResultadoDeCaptura();
}

/// La foto, tal como salió de la cámara o de la galería (sin achicar).
final class FotoCapturada extends ResultadoDeCaptura {
  const FotoCapturada(this.bytes);
  final Uint8List bytes;
}

/// El colportor cerró la cámara o la galería sin elegir nada.
final class CapturaCancelada extends ResultadoDeCaptura {
  const CapturaCancelada();
}

/// El teléfono no deja usar la cámara (o la galería): hay que activarlo en los ajustes (29C-07).
final class CapturaSinPermiso extends ResultadoDeCaptura {
  const CapturaSinPermiso();
}

/// La cámara o la galería fallaron por otra causa (sin cámara, archivo ilegible).
final class CapturaFallida extends ResultadoDeCaptura {
  const CapturaFallida();
}

/// La cámara nativa y la galería del teléfono (HU-COB-007: «Cámara nativa o desde galería»). Un
/// adaptador sobre una librería de cámara lo implementa; **todavía no hay adaptador de producción**:
/// elegir la librería es una decisión de stack que espera a Cristian (pendiente del issue #427), y
/// hasta entonces la vista no ofrece «Sacar foto del ticket».
abstract interface class CapturadorDeFoto {
  /// Abre la cámara y devuelve la foto que se sacó. Nunca lanza.
  Future<ResultadoDeCaptura> sacarFoto();

  /// Abre la galería y devuelve la foto que se eligió. Nunca lanza.
  Future<ResultadoDeCaptura> elegirDeLaGaleria();

  /// Lleva a los ajustes del teléfono, a donde se activa el permiso de la cámara. Nunca lanza.
  Future<void> abrirLosAjustes();
}

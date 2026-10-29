import 'dart:typed_data';

/// Lo que devuelve la cámara o la galería.
sealed class ResultadoDeCaptura {
  const ResultadoDeCaptura();
}

/// Llegó la foto, tal como salió del teléfono (sin comprimir).
final class FotoCapturada extends ResultadoDeCaptura {
  const FotoCapturada(this.bytes);

  final Uint8List bytes;
}

/// La colportora cerró la cámara o la galería sin elegir nada.
final class CapturaCancelada extends ResultadoDeCaptura {
  const CapturaCancelada();
}

/// El teléfono no dejó usar la cámara (permiso negado): 29C·07.
final class CapturaSinPermiso extends ResultadoDeCaptura {
  const CapturaSinPermiso();
}

/// La cámara o la galería fallaron por otra causa.
final class CapturaFallida extends ResultadoDeCaptura {
  const CapturaFallida();
}

/// La cámara y la galería del teléfono (HU-COB-007: «cámara nativa o desde galería»).
///
/// **Sin implementación de producción todavía**: la librería (cámara y galería) es una decisión de stack
/// que espera a Cristian (ver el pendiente del PR). Hasta entonces `capturadorDeFotoProvider` es `null` y
/// la app no ofrece «Sacar foto del ticket».
abstract interface class CapturadorDeFoto {
  /// Abre la cámara.
  Future<ResultadoDeCaptura> sacarFoto();

  /// Abre la galería.
  Future<ResultadoDeCaptura> elegirDeLaGaleria();

  /// Abre los ajustes del teléfono para dar el permiso de la cámara.
  Future<void> abrirAjustes();
}

/// Una foto ya comprimida.
final class ImagenComprimida {
  const ImagenComprimida({required this.bytes, required this.tipoDeImagen});

  final Uint8List bytes;

  /// `image/jpeg`, `image/png` o `image/webp`.
  final String tipoDeImagen;
}

/// Comprime una foto. Misma observación que [CapturadorDeFoto]: sin implementación de producción hasta
/// que Cristian decida la librería.
abstract interface class CompresorDeImagen {
  /// Comprime [original] con [calidad] (1 a 100) y el lado mayor de hasta [ladoMaximo] píxeles. `null` si
  /// no se puede leer la imagen.
  Future<ImagenComprimida?> comprimir(
    Uint8List original, {
    required int calidad,
    required int ladoMaximo,
  });
}

/// Dónde se guarda la copia local de la foto (archivos de la app).
abstract interface class AlmacenDeFotos {
  /// Guarda [bytes] como la copia del ticket [ticketId] y devuelve su ruta.
  Future<String> guardar(String ticketId, Uint8List bytes, String extension);

  /// Los bytes del archivo, o `null` si ya no está.
  Future<Uint8List?> leer(String ruta);

  /// Borra el archivo; no falla si no existe.
  Future<void> borrar(String ruta);
}

/// Cómo terminó el intento de subir una foto.
sealed class ResultadoDeSubida {
  const ResultadoDeSubida();
}

/// La foto quedó en el bucket, en [ruta] (`<usuario_id>/<ticket_id>.<ext>`).
final class SubidaLista extends ResultadoDeSubida {
  const SubidaLista(this.ruta);

  final String ruta;
}

/// No hay conexión (o se cortó): se reintenta sola cuando vuelva.
final class SubidaSinConexion extends ResultadoDeSubida {
  const SubidaSinConexion();
}

/// La sesión venció: hay que volver a entrar. La foto y el ticket siguen en el teléfono.
final class SubidaSinSesion extends ResultadoDeSubida {
  const SubidaSinSesion();
}

/// El servidor no la aceptó o falló ([codigo], para el log): queda guardada y se reintenta.
final class SubidaFallida extends ResultadoDeSubida {
  const SubidaFallida(this.codigo);

  final String codigo;
}

/// La foto del ticket al bucket privado: pide el enlace firmado a la Edge Function `foto-ticket` y hace
/// el `PUT` con las cabeceras que ella devuelve (backend-supabase#182). El teléfono nunca habla con R2 con
/// claves propias.
abstract interface class SubidorDeFoto {
  /// Sube [bytes]. [alProgreso] recibe de 0 a 1.
  Future<ResultadoDeSubida> subir({
    required String ticketId,
    required String tipoDeImagen,
    required Uint8List bytes,
    void Function(double progreso)? alProgreso,
  });
}

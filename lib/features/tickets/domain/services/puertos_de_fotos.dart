import 'dart:typed_data';

import '../entities/ticket.dart';

/// Dónde se guarda en el teléfono la copia comprimida de la foto de un ticket (supuesto S41). Un
/// adaptador la deja en el directorio privado de la app.
abstract interface class AlmacenDeFotosDeTicket {
  /// Guarda [bytes] como la copia del ticket [ticketId] y devuelve su ruta. Pisa una copia anterior
  /// del mismo ticket.
  Future<String> guardar(String ticketId, TipoDeImagen tipo, Uint8List bytes);

  /// Los bytes de la copia, o `null` si el archivo ya no está.
  Future<Uint8List?> leer(String ruta);

  /// Borra la copia; si ya no estaba, no falla.
  Future<void> borrar(String ruta);
}

/// Cómo terminó el intento de subir una foto.
sealed class ResultadoDeSubidaDeFoto {
  const ResultadoDeSubidaDeFoto();
}

/// La foto quedó en el bucket en [ruta] (`<usuario_id>/<ticket_id>.<ext>`).
final class FotoSubida extends ResultadoDeSubidaDeFoto {
  const FotoSubida(this.ruta);
  final String ruta;
}

/// El servidor ya tenía la foto (`409 foto_ya_subida`: un intento anterior llegó a R2 pero su
/// respuesta se perdió). Se toma como «la foto ya está» y se sigue.
final class FotoYaEstaba extends ResultadoDeSubidaDeFoto {
  const FotoYaEstaba(this.ruta);
  final String ruta;
}

/// No se pudo subir. Si [reintentable], más tarde puede salir (sin red, sin sesión, servidor caído,
/// ticket que todavía no llegó); si no, reintentar no lo arregla (foto de más de 2 MiB, tipo que el
/// servidor no acepta). [codigo] es estable y sin texto del servidor ni de la foto.
final class SubidaFallida extends ResultadoDeSubidaDeFoto {
  const SubidaFallida({required this.codigo, required this.reintentable});
  final String codigo;
  final bool reintentable;
}

/// La subida de la foto al bucket privado (R2) por el enlace firmado de la Edge Function
/// `foto-ticket`. El teléfono no habla con R2 con claves: pide el enlace (vence a los 10 minutos) y
/// hace el `PUT` con las cabeceras exactas que devolvió la función. Un adaptador sobre Supabase y
/// `http` la implementa.
abstract interface class ServidorDeFotosDeTicket {
  /// Sube [bytes] como la foto del ticket [ticketId]. Nunca lanza: todo fallo es [SubidaFallida].
  Future<ResultadoDeSubidaDeFoto> subir({
    required String ticketId,
    required TipoDeImagen tipo,
    required Uint8List bytes,
  });
}

/// Achica una imagen. El adaptador usa una librería de imágenes (ver la pendiente de stack del
/// issue); la política de cuánto achicar es de `PoliticaDeCompresion`.
abstract interface class CompresorDeImagen {
  /// Devuelve [original] como JPEG con el lado mayor de a lo sumo [ladoMaximo] píxeles y la
  /// [calidad] dada (1 a 100), o `null` si no la puede leer como imagen.
  Future<Uint8List?> comprimirComoJpeg(
    Uint8List original, {
    required int ladoMaximo,
    required int calidad,
  });
}

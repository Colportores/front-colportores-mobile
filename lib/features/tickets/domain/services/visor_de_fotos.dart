import 'dart:typed_data';

/// Qué hay para mostrar de la foto de un ticket (38B·02, 38B·03).
sealed class FotoParaVer {
  const FotoParaVer();
}

/// La copia que quedó en el teléfono.
final class FotoEnElTelefono extends FotoParaVer {
  const FotoEnElTelefono(this.bytes);
  final Uint8List bytes;
}

/// La foto está en la nube: [url] es un enlace firmado que vence a los 5 minutos.
final class FotoEnLaNube extends FotoParaVer {
  const FotoEnLaNube(this.url);
  final Uri url;
}

/// Pasaron los 4 meses y el servidor ya no tiene la foto (HU-COB-009, «Foto vencida»): los datos del
/// ticket siguen, la foto no.
final class FotoVencida extends FotoParaVer {
  const FotoVencida();
}

/// Todavía no hay foto que ver: el ticket no la subió y la copia ya no está.
final class SinFotoParaVer extends FotoParaVer {
  const SinFotoParaVer();
}

/// No se pudo pedir la foto. Con [sinRed] es que no hay conexión: al volver se puede reintentar.
final class FotoNoDisponible extends FotoParaVer {
  const FotoNoDisponible({this.sinRed = false});
  final bool sinRed;
}

/// Pide el enlace para ver la foto de un ticket que ya está en la nube (Edge Function `foto-ticket`,
/// acción `ver`; HU-COB-009: «la foto se pide al cloud»). Nunca lanza: todo fallo es [FotoNoDisponible].
abstract interface class VisorDeFotosDeTicket {
  Future<FotoParaVer> ver(String ticketId);
}

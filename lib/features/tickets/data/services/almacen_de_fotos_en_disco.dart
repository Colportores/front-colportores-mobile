import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../domain/entities/ticket.dart';
import '../../domain/services/puertos_de_fotos.dart';

/// [AlmacenDeFotosDeTicket] sobre el sistema de archivos: la copia comprimida de cada foto queda en
/// una carpeta `tickets/` dentro del directorio privado de la app (no en la galería), con el id del
/// ticket como nombre. Escribe a un temporal y renombra, así un corte a mitad no deja una foto
/// cortada con el nombre del ticket.
final class AlmacenDeFotosEnDisco implements AlmacenDeFotosDeTicket {
  /// [directorioBase] es el directorio privado de la app (`getApplicationSupportDirectory()`).
  AlmacenDeFotosEnDisco(String directorioBase)
    : _carpeta = Directory(p.join(directorioBase, 'tickets'));

  final Directory _carpeta;

  @override
  Future<String> guardar(String ticketId, TipoDeImagen tipo, Uint8List bytes) async {
    await _carpeta.create(recursive: true);
    final destino = File(p.join(_carpeta.path, '$ticketId.${tipo.extension}'));
    final temporal = File('${destino.path}.parcial');
    await temporal.writeAsBytes(bytes, flush: true);
    await temporal.rename(destino.path);
    return destino.path;
  }

  @override
  Future<Uint8List?> leer(String ruta) async {
    final archivo = File(ruta);
    return await archivo.exists() ? archivo.readAsBytes() : null;
  }

  @override
  Future<void> borrar(String ruta) async {
    final archivo = File(ruta);
    if (await archivo.exists()) await archivo.delete();
  }
}

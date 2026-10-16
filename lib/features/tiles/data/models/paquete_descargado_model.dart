import 'package:path/path.dart' as p;

import '../../domain/entities/paquete_tiles.dart';
import 'paquete_tiles_model.dart';

/// [PaqueteDescargado] como lo guarda el manifiesto `registro.json`: el paquete del catálogo con el
/// que se descargó y los nombres de sus archivos, sin la carpeta (la ruta absoluta de la app puede
/// cambiar entre una versión y otra, y de un teléfono a otro si se restaura una copia).
///
/// Un registro que no se puede leer lanza [FormatException]: quien lee descarta esa entrada.
abstract final class PaqueteDescargadoModel {
  static Map<String, dynamic> aJson(PaqueteDescargado descargado) {
    return {
      'paquete': PaqueteTilesModel.aJson(descargado.paquete),
      'archivos': [for (final ruta in descargado.rutas) p.basename(ruta)],
    };
  }

  /// Lee una entrada del manifiesto; las rutas quedan dentro de [directorio].
  static PaqueteDescargado desdeJson(Object? json, String directorio) {
    if (json is! Map<String, dynamic>) throw const FormatException('registro inválido');
    final paquete = json['paquete'];
    final archivos = json['archivos'];
    if (paquete is! Map<String, dynamic> || archivos is! List<dynamic>) {
      throw const FormatException('registro incompleto');
    }
    final partes = paquete['partes'];
    if (partes is! List<dynamic> || partes.isEmpty || partes.length != archivos.length) {
      throw const FormatException('registro con partes que no coinciden con los archivos');
    }
    return PaqueteDescargado(
      paquete: PaqueteTilesModel.desdeJson(paquete),
      rutas: [for (final archivo in archivos) p.join(directorio, _nombre(archivo))],
    );
  }

  /// El nombre de un archivo del directorio: nunca una ruta, así un manifiesto alterado no saca a
  /// la app del directorio de los paquetes.
  static String _nombre(Object? archivo) {
    if (archivo is! String || archivo.isEmpty || archivo != p.basename(archivo)) {
      throw const FormatException('nombre de archivo inválido');
    }
    return archivo;
  }
}

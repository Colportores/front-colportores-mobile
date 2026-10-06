import 'package:path/path.dart' as p;

import '../../domain/entities/paquete_tiles.dart';

/// [PaqueteDescargado] como lo guarda el manifiesto `registro.json`: el paquete del catálogo con el
/// que se descargó y los nombres de sus archivos, sin la carpeta (la ruta absoluta de la app puede
/// cambiar entre una versión y otra, y de un teléfono a otro si se restaura una copia).
///
/// Un registro que no se puede leer lanza [FormatException]: quien lee descarta esa entrada.
abstract final class PaqueteDescargadoModel {
  static Map<String, dynamic> aJson(PaqueteDescargado descargado) {
    final paquete = descargado.paquete;
    return {
      'paquete': {
        'id': paquete.id,
        'nivel': paquete.nivel.name,
        'ambito_id': paquete.ambitoId,
        'nombre': paquete.nombre,
        'version': paquete.version,
        'partes': [
          for (final parte in paquete.partes)
            {
              'origen': parte.origen.toString(),
              'tamano_bytes': parte.tamanoBytes,
              'sha256': parte.sha256,
            },
        ],
      },
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
    final nivel = NivelCobertura.values.asNameMap()[paquete['nivel']];
    final id = paquete['id'];
    final version = paquete['version'];
    final ambito = paquete['ambito_id'];
    final nombre = paquete['nombre'];
    if (nivel == null || id is! String || version is! String) {
      throw const FormatException('registro con campos inválidos');
    }
    return PaqueteDescargado(
      paquete: PaqueteTiles(
        id: id,
        nivel: nivel,
        ambitoId: ambito is String ? ambito : null,
        nombre: nombre is String ? nombre : null,
        version: version,
        partes: [for (final parte in partes) _parte(parte)],
      ),
      rutas: [for (final archivo in archivos) p.join(directorio, _nombre(archivo))],
    );
  }

  static ParteTiles _parte(Object? json) {
    if (json is! Map<String, dynamic>) throw const FormatException('parte inválida');
    final origen = json['origen'];
    final tamano = json['tamano_bytes'];
    final sha = json['sha256'];
    final uri = origen is String ? Uri.tryParse(origen) : null;
    if (uri == null || tamano is! int || sha is! String) {
      throw const FormatException('parte con campos inválidos');
    }
    return ParteTiles(origen: uri, tamanoBytes: tamano, sha256: sha);
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

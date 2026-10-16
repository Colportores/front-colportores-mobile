import '../../domain/entities/paquete_tiles.dart';

/// [PaqueteTiles] como lo guardan los manifiestos del teléfono (`registro.json` y
/// `descargas_pendientes.json`): el paquete del catálogo con el que se descargó, sin ninguna ruta
/// local. Lo que no se puede leer lanza [FormatException]: quien lee descarta esa entrada.
abstract final class PaqueteTilesModel {
  static Map<String, dynamic> aJson(PaqueteTiles paquete) {
    return {
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
    };
  }

  static PaqueteTiles desdeJson(Map<String, dynamic> paquete) {
    final partes = paquete['partes'];
    final nivel = NivelCobertura.values.asNameMap()[paquete['nivel']];
    final id = paquete['id'];
    final version = paquete['version'];
    final ambito = paquete['ambito_id'];
    final nombre = paquete['nombre'];
    if (partes is! List<dynamic> || partes.isEmpty) {
      throw const FormatException('paquete sin partes');
    }
    if (nivel == null || id is! String || version is! String) {
      throw const FormatException('registro con campos inválidos');
    }
    return PaqueteTiles(
      id: id,
      nivel: nivel,
      ambitoId: ambito is String ? ambito : null,
      nombre: nombre is String ? nombre : null,
      version: version,
      partes: [for (final parte in partes) _parte(parte)],
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
}

import 'dart:convert';

import '../../domain/entities/paquete_tiles.dart';

/// El `catalogo.json` del bucket público `mapas` (backend-supabase, `docs/mapas-tiles.md`, § El
/// catálogo) como lista de [PaqueteTiles].
///
/// Lee solo lo que la app usa: `id`, `nivel`, `ambito_id`, `nombre`, `version` y de cada parte
/// `archivo`, `tamano_bytes` y `sha256`. Lo demás (`bbox`, `zoom_*`, `fuente_build`, `retirados`,
/// `estilo`) lo ignora: `retirados` es del publicador, y el estilo y los recursos del mapa viajan
/// dentro de la app.
///
/// El catálogo es público y lo escribe otro sistema: un paquete que no cumple el contrato (sin
/// partes, con un checksum que no es un SHA-256, con un `id` que no sirve de nombre de archivo,
/// con una ruta que se sale del bucket) se descarta solo, sin tirar el resto. Un catálogo que no
/// es JSON o de otra versión del formato lanza [FormatException].
abstract final class CatalogoTilesModel {
  /// La versión del formato que entiende esta app.
  static const versionFormato = 1;

  static final _idValido = RegExp(r'^[A-Za-z0-9_-]{1,80}$');
  static final _sha256Valido = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Lee [texto] resolviendo las rutas de las partes contra [base], la URL del catálogo. Cada
  /// paquete descartado se avisa por [descartado] con su id (si lo tenía) y el motivo.
  static List<PaqueteTiles> desdeJson(
    String texto,
    Uri base, {
    void Function(String? id, String motivo)? descartado,
  }) {
    final Object? raiz;
    try {
      raiz = jsonDecode(texto);
    } on FormatException catch (e) {
      throw FormatException('el catálogo no es JSON: ${e.message}');
    }
    if (raiz is! Map<String, dynamic>) throw const FormatException('el catálogo no es un objeto');
    if (raiz['version'] != versionFormato) {
      throw FormatException('versión del catálogo no soportada: ${raiz['version']}');
    }
    final lista = raiz['paquetes'];
    if (lista is! List<dynamic>) throw const FormatException('el catálogo no trae paquetes');

    final paquetes = <PaqueteTiles>[];
    final vistos = <String>{};
    for (final item in lista) {
      final id = item is Map<String, dynamic> && item['id'] is String ? item['id'] as String : null;
      try {
        if (item is! Map<String, dynamic>) throw const FormatException('no es un objeto');
        final paquete = _paquete(item, base);
        if (!vistos.add(paquete.id)) throw const FormatException('id repetido');
        paquetes.add(paquete);
      } on FormatException catch (e) {
        descartado?.call(id, e.message);
      }
    }
    return paquetes;
  }

  static PaqueteTiles _paquete(Map<String, dynamic> json, Uri base) {
    final id = json['id'];
    if (id is! String || !_idValido.hasMatch(id)) throw const FormatException('id inválido');
    final nivel = _nivel(json['nivel']);
    final ambito = json['ambito_id'];
    final ambitoId = ambito is String && ambito.trim().isNotEmpty ? ambito.trim() : null;
    if (nivel != NivelCobertura.uruguay && ambitoId == null) {
      throw const FormatException('falta ambito_id');
    }
    final version = json['version'];
    if (version is! String || version.trim().isEmpty) throw const FormatException('sin version');
    final nombre = json['nombre'];
    final partes = json['partes'];
    if (partes is! List<dynamic> || partes.isEmpty) throw const FormatException('sin partes');
    return PaqueteTiles(
      id: id,
      nivel: nivel,
      ambitoId: nivel == NivelCobertura.uruguay ? null : ambitoId,
      nombre: nombre is String && nombre.trim().isNotEmpty ? nombre.trim() : null,
      version: version,
      partes: [
        for (final parte in partes)
          _parte(parte is Map<String, dynamic> ? parte : const <String, dynamic>{}, base),
      ],
    );
  }

  static NivelCobertura _nivel(Object? valor) {
    for (final nivel in NivelCobertura.values) {
      if (nivel.name == valor) return nivel;
    }
    throw FormatException('nivel desconocido: $valor');
  }

  static ParteTiles _parte(Map<String, dynamic> json, Uri base) {
    final archivo = json['archivo'];
    final tamano = json['tamano_bytes'];
    final sha = json['sha256'];
    if (archivo is! String) throw const FormatException('parte sin archivo');
    if (tamano is! int || tamano <= 0) throw const FormatException('parte con tamaño inválido');
    if (sha is! String || !_sha256Valido.hasMatch(sha)) {
      throw const FormatException('parte con sha256 inválido');
    }
    return ParteTiles(
      origen: _resolver(base, archivo),
      tamanoBytes: tamano,
      sha256: sha.toLowerCase(),
    );
  }

  /// [archivo] contra [base]. Tiene que ser una ruta relativa que quede en el mismo servidor y en
  /// el mismo directorio del catálogo o debajo: ni `..` ni `.` (se mira el texto crudo: `Uri` los
  /// normaliza), ni `//host`, ni un esquema propio.
  static Uri _resolver(Uri base, String archivo) {
    final relativa = Uri.tryParse(archivo);
    if (relativa == null ||
        archivo.isEmpty ||
        relativa.hasScheme ||
        relativa.hasAuthority ||
        relativa.hasQuery ||
        relativa.hasFragment ||
        relativa.path.startsWith('/') ||
        archivo.split('/').any((segmento) => segmento == '..' || segmento == '.')) {
      throw FormatException('ruta de parte inválida: $archivo');
    }
    return base.resolveUri(relativa);
  }
}

// Los archivos del estilo del mapa en disco, para los tests que los leen sin el bundle: desde #673 no
// están en `assets/mapa/` de la app sino en el paquete `colportores_mapa` (lib-mapa), en la caché de
// pub. Se ubica por `.dart_tool/package_config.json`, el mismo que usa `flutter test`.
import 'dart:convert';
import 'dart:io';

/// La carpeta `assets/mapa/` del paquete `colportores_mapa`.
Directory carpetaAssetsDeLibMapa() {
  final config = File('.dart_tool/package_config.json').absolute;
  final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final paquete = (json['packages'] as List<dynamic>).cast<Map<String, dynamic>>().firstWhere(
    (p) => p['name'] == 'colportores_mapa',
  );
  var raiz = paquete['rootUri'] as String;
  if (!raiz.endsWith('/')) raiz = '$raiz/';
  return Directory.fromUri(config.uri.resolve(raiz).resolve('assets/mapa/'));
}

/// El archivo [relativa] (por ejemplo `estilo/colportores.json`) de `assets/mapa/` del paquete.
File archivoDeLibMapa(String relativa) =>
    File.fromUri(carpetaAssetsDeLibMapa().uri.resolve(relativa));

/// La carpeta [relativa] (por ejemplo `glyphs/NotoSans-Regular`) de `assets/mapa/` del paquete.
Directory carpetaDeLibMapa(String relativa) =>
    Directory.fromUri(carpetaAssetsDeLibMapa().uri.resolve(relativa));

/// El estilo del mapa tal como viaja en el paquete.
String estiloDeLibMapa() => archivoDeLibMapa('estilo/colportores.json').readAsStringSync();

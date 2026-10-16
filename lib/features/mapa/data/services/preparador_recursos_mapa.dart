import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Deja en el almacenamiento interno de la app los glyphs (tipografías) y sprites (íconos) del
/// estilo del mapa.
///
/// Van adentro de la app para que el mapa offline no necesite red, pero MapLibre los lee con
/// `file://`: no sabe abrir los assets de Flutter. Por eso se copian una vez a
/// `<soporte>/mapa/<versión>/` (el almacenamiento interno: la capa nativa no puede leer el
/// externo, `Android/data/…`). Subir [version] cuando cambia algo de `assets/mapa/`.
class PreparadorRecursosMapa {
  PreparadorRecursosMapa({
    required this._directorioBase,
    AssetBundle? bundle,
    this.version = versionRecursosMapa,
  }) : _bundle = bundle ?? rootBundle;

  /// Los glyphs y sprites de `@protomaps/basemaps` 5.7.2 que publica backend (#42). Sumar uno a la
  /// versión cuando se cambian los archivos de `assets/mapa/`.
  static const versionRecursosMapa = 'basemaps-5.7.2-2';

  static const _raizAssets = 'assets/mapa/';
  static const _carpetas = ['glyphs/', 'sprites/'];
  static const _marcaListo = '.listo';

  final Future<Directory> Function() _directorioBase;
  final AssetBundle _bundle;
  final String version;

  Future<String>? _enCurso;

  /// La ruta del directorio con `glyphs/` y `sprites/` listos. La primera vez copia; las demás,
  /// solo comprueba que la copia anterior terminó. Varias llamadas a la vez comparten la copia.
  Future<String> preparar() => _enCurso ??= _preparar().whenComplete(() => _enCurso = null);

  Future<String> _preparar() async {
    final base = await _directorioBase();
    final raiz = Directory(p.join(base.path, 'mapa'));
    final destino = Directory(p.join(raiz.path, version));
    if (File(p.join(destino.path, _marcaListo)).existsSync()) return destino.path;

    final temporal = Directory(p.join(raiz.path, '$version.tmp'));
    if (temporal.existsSync()) await temporal.delete(recursive: true);
    await temporal.create(recursive: true);

    final manifiesto = await AssetManifest.loadFromAssetBundle(_bundle);
    for (final clave in manifiesto.listAssets()) {
      if (!clave.startsWith(_raizAssets)) continue;
      final relativa = clave.substring(_raizAssets.length);
      if (!_carpetas.any(relativa.startsWith)) continue;
      final datos = await _bundle.load(clave);
      final archivo = File(p.join(temporal.path, relativa));
      await archivo.parent.create(recursive: true);
      await archivo.writeAsBytes(
        datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes),
        flush: true,
      );
    }
    await File(p.join(temporal.path, _marcaListo)).writeAsString(version, flush: true);

    if (destino.existsSync()) await destino.delete(recursive: true);
    await temporal.rename(destino.path);
    await _borrarVersionesViejas(raiz, conservar: destino.path);
    return destino.path;
  }

  Future<void> _borrarVersionesViejas(Directory raiz, {required String conservar}) async {
    await for (final entrada in raiz.list()) {
      if (entrada is Directory && entrada.path != conservar) {
        await entrada.delete(recursive: true);
      }
    }
  }
}

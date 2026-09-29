import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/services/puertos_descarga.dart';

/// [ArchivosTiles] con `dart:io`, dentro de [_directorio]: el directorio de la app para los
/// paquetes. Qué directorio exacto (soporte de la app, documentos) lo fija quien arme el provider.
final class ArchivosTilesIo implements ArchivosTiles {
  ArchivosTilesIo(this._directorio);

  final Directory _directorio;

  static final _idValido = RegExp(r'^[A-Za-z0-9_-]+$');

  @override
  String rutaFinal(String paqueteId) {
    return p.join(_directorio.path, '${_validado(paqueteId)}.pmtiles');
  }

  @override
  String rutaParcial(String paqueteId) => '${rutaFinal(paqueteId)}.part';

  @override
  Future<int> tamano(String ruta) async {
    final archivo = File(ruta);
    if (!await archivo.exists()) return 0;
    return archivo.length();
  }

  @override
  Future<bool> existe(String ruta) => File(ruta).exists();

  @override
  Future<EscrituraArchivo> abrir(String ruta, {required bool anexar}) async {
    await _directorio.create(recursive: true);
    final modo = anexar ? FileMode.append : FileMode.write;
    return _EscrituraIo(File(ruta).openWrite(mode: modo));
  }

  /// En Android e iOS `rename` reemplaza el destino de una vez: nunca queda un `.pmtiles` a medias.
  @override
  Future<void> renombrar(String desde, String hasta) async {
    await File(desde).rename(hasta);
  }

  @override
  Future<void> borrar(String ruta) async {
    final archivo = File(ruta);
    if (await archivo.exists()) await archivo.delete();
  }

  /// El id nombra el archivo: solo letras, números, `-` y `_`, así no se sale del directorio.
  static String _validado(String paqueteId) {
    if (!_idValido.hasMatch(paqueteId)) throw ArgumentError.value(paqueteId, 'paqueteId');
    return paqueteId;
  }
}

final class _EscrituraIo implements EscrituraArchivo {
  _EscrituraIo(this._sink);

  final IOSink _sink;

  @override
  void agregar(List<int> bytes) => _sink.add(bytes);

  @override
  Future<void> cerrar() async {
    await _sink.close();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/services/puertos_descarga.dart';

/// [ArchivosTiles] con `dart:io`, dentro de [_directorio]: el directorio de la app para los
/// paquetes (`<soporte de la app>/tiles`, ver `ComposicionTiles`). Es el almacenamiento
/// interno: MapLibre solo lee `pmtiles://file://` de ahí.
final class ArchivosTilesIo implements ArchivosTiles {
  ArchivosTilesIo(this._directorio);

  final Directory _directorio;

  static final _claveValida = RegExp(r'^[A-Za-z0-9_-]+$');

  /// `ENOSPC` en Android, iOS y Linux; `ERROR_DISK_FULL` en Windows.
  static const _sinLugar = {28, 112};

  @override
  String rutaFinal(String clave) {
    return p.join(_directorio.path, '${_validada(clave)}${ArchivoTiles.extensionFinal}');
  }

  @override
  String rutaParcial(String clave) {
    return p.join(_directorio.path, '${_validada(clave)}${ArchivoTiles.extensionParcial}');
  }

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

  @override
  Future<List<ArchivoTiles>> listar() async {
    if (!await _directorio.exists()) return const [];
    final archivos = <ArchivoTiles>[];
    await for (final entidad in _directorio.list(followLinks: false)) {
      if (entidad is! File) continue;
      final nombre = p.basename(entidad.path);
      if (!nombre.endsWith(ArchivoTiles.extensionFinal) &&
          !nombre.endsWith(ArchivoTiles.extensionParcial)) {
        continue;
      }
      final datos = await entidad.stat();
      archivos.add(
        ArchivoTiles(
          nombre: nombre,
          ruta: entidad.path,
          bytes: datos.size,
          modificado: datos.modified,
        ),
      );
    }
    return archivos;
  }

  /// La clave nombra el archivo: solo letras, números, `-` y `_`, así no se sale del directorio.
  static String _validada(String clave) {
    if (!_claveValida.hasMatch(clave)) throw ArgumentError.value(clave, 'clave');
    return clave;
  }

  /// Un error de escritura por disco lleno sale como [ErrorEspacioTiles].
  static Never _fallar(Object error, StackTrace pila) {
    if (error is FileSystemException && _sinLugar.contains(error.osError?.errorCode)) {
      Error.throwWithStackTrace(ErrorEspacioTiles(error), pila);
    }
    Error.throwWithStackTrace(error, pila);
  }
}

final class _EscrituraIo implements EscrituraArchivo {
  _EscrituraIo(this._sink) {
    // Un fallo de escritura le llega a quien espera `agregar` o `cerrar`; `done` lo repite y, sin
    // nadie escuchando, se reportaría como un error sin atrapar.
    unawaited(_sink.done.then((_) {}, onError: (Object _) {}));
  }

  final IOSink _sink;

  /// La última escritura pedida, sin su error (ese le llega a quien esperó `agregar`). Un `IOSink`
  /// no admite `add`, `flush` ni `close` mientras un `flush` está pendiente («StreamSink is bound to
  /// a stream»): pausar, eliminar o perder el Wi-Fi corta la descarga justo ahí, así que `cerrar`
  /// y cada `agregar` esperan a esta antes de tocar el sink.
  Future<void> _enVuelo = Future<void>.value();

  /// `flush` espera a que el pedazo salga al archivo: es lo que le da contrapresión a la descarga.
  @override
  Future<void> agregar(List<int> bytes) {
    final escritura = _enVuelo.then((_) => _escribir(bytes));
    _enVuelo = escritura.then((_) {}, onError: (Object _) {});
    return escritura;
  }

  Future<void> _escribir(List<int> bytes) async {
    try {
      _sink.add(bytes);
      await _sink.flush();
    } on Object catch (e, pila) {
      ArchivosTilesIo._fallar(e, pila);
    }
  }

  /// Espera a la escritura en vuelo (si la hay) y cierra: el pedazo que ya salió hacia el disco
  /// queda entero en el `.part`, que es lo que la descarga retoma con `Range`.
  @override
  Future<void> cerrar() async {
    await _enVuelo;
    try {
      await _sink.close();
    } on Object catch (e, pila) {
      ArchivosTilesIo._fallar(e, pila);
    }
  }
}

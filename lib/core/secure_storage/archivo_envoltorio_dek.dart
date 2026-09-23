import 'dart:io';

import 'package:path/path.dart' as p;

import 'envoltorio_dek.dart';

/// Archivo común donde vive la DEK envuelta con la contraseña (ADR-006).
///
/// Va **fuera** del almacén seguro a propósito: ya está cifrada, y así un `deleteAll()` del almacén
/// —el de la recuperación guiada, o un Keystore que se rompe— no se la lleva. Es la copia que deja
/// reconstruir el almacén con la contraseña y la que viaja con el backup.
///
/// Lanza [ArchivoEnvoltorioException] ante fallas de disco y [EnvoltorioCorruptoException] si lo
/// que hay no se puede interpretar; el consumidor las traduce a `Failure`.
final class ArchivoEnvoltorioDek {
  ArchivoEnvoltorioDek({required this._directorio, this._nombreArchivo = nombreArchivoPorDefecto});

  /// La doc del proyecto no fija nombre ni ruta; en `main.dart` el directorio es el mismo de la DB
  /// (`getApplicationDocumentsDirectory()`).
  static const String nombreArchivoPorDefecto = 'dek_envuelta.json';

  final Future<Directory> Function() _directorio;
  final String _nombreArchivo;

  Future<File> _archivo() async => File(p.join((await _directorio()).path, _nombreArchivo));

  /// Si hay un envoltorio guardado. No dice si se puede abrir.
  Future<bool> existe() => _io('existe', () async => (await _archivo()).exists());

  /// El envoltorio guardado, o `null` si no hay ninguno.
  Future<EnvoltorioDek?> leer() async {
    final texto = await _io('leer', () async {
      final archivo = await _archivo();
      return await archivo.exists() ? archivo.readAsString() : null;
    });
    return texto == null ? null : EnvoltorioDek.decodificar(texto);
  }

  /// Guarda [envoltorio], reemplazando el anterior **de forma atómica**: se escribe un archivo
  /// temporal y se renombra encima. Si la app muere a mitad de camino queda el envoltorio anterior
  /// entero, nunca uno a medio escribir.
  Future<void> escribir(EnvoltorioDek envoltorio) => _io('escribir', () async {
    final archivo = await _archivo();
    final temporal = File('${archivo.path}.tmp');
    await temporal.writeAsString(envoltorio.codificar(), flush: true);
    await temporal.rename(archivo.path);
  });

  /// Borra el envoltorio (y el temporal, si quedó). Si no había, no hace nada.
  Future<void> borrar() => _io('borrar', () async {
    final archivo = await _archivo();
    for (final f in [archivo, File('${archivo.path}.tmp')]) {
      if (await f.exists()) await f.delete();
    }
  });

  Future<T> _io<T>(String operacion, Future<T> Function() accion) async {
    try {
      return await accion();
    } on FileSystemException catch (e) {
      throw ArchivoEnvoltorioException(operacion: operacion, causa: e);
    }
  }
}

/// Falla de disco al leer, escribir o borrar el archivo del envoltorio. [causa] va a logs, nunca al
/// usuario; [toString] no lleva la ruta.
final class ArchivoEnvoltorioException implements Exception {
  const ArchivoEnvoltorioException({required this.operacion, this.causa});

  /// `existe`, `leer`, `escribir` o `borrar`.
  final String operacion;

  final FileSystemException? causa;

  @override
  String toString() => 'ArchivoEnvoltorioException($operacion)';
}

import 'dart:io';

import 'package:path/path.dart' as p;

import 'envoltorio_dek.dart';

/// Archivo común donde vive la DEK envuelta con la contraseña (ADR-006).
///
/// Va **fuera** del almacén seguro a propósito: ya está cifrada, y así un `deleteAll()` del almacén
/// —el de la recuperación guiada, o un Keystore que se rompe— no se la lleva. Es la copia que deja
/// reconstruir el almacén con la contraseña y la que viaja con el backup.
///
/// Al lado guarda la marca de **desactualizado** (#125): un archivo con el `usuario_id` de quien
/// empezó a cambiar la contraseña y no llegó a re-envolver, así que el envoltorio puede estar
/// hecho con una contraseña que ya no es la de esa cuenta. Vive en disco, como el envoltorio, para
/// que un Keystore que falla no se la lleve.
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

  Future<File> _marcaDesactualizado() async => File('${(await _archivo()).path}.desactualizado');

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
  ///
  /// Después baja la marca de desactualizado: un envoltorio nuevo siempre se arma con la
  /// contraseña vigente. Si no se puede bajar, queda puesta y no pasa nada grave: el próximo login
  /// con contraseña vuelve a envolver.
  Future<void> escribir(EnvoltorioDek envoltorio) async {
    await _io('escribir', () async {
      final archivo = await _archivo();
      final temporal = File('${archivo.path}.tmp');
      await temporal.writeAsString(envoltorio.codificar(), flush: true);
      await temporal.rename(archivo.path);
    });
    try {
      final marca = await _marcaDesactualizado();
      if (await marca.exists()) await marca.delete();
    } on FileSystemException {
      // Ver arriba: una marca que queda de más solo cuesta un Argon2id en el próximo login.
    }
  }

  /// El `usuario_id` que guardó [marcarDesactualizado], o `null` si el envoltorio no está marcado
  /// como desactualizado.
  Future<String?> desactualizadoPara() => _io('marca', () async {
    final marca = await _marcaDesactualizado();
    return await marca.exists() ? (await marca.readAsString()).trim() : null;
  });

  /// Marca el envoltorio como desactualizado por un cambio de contraseña de [usuarioId]: puede
  /// estar hecho con una contraseña que ya no es la de esa cuenta. La baja el próximo [escribir].
  Future<void> marcarDesactualizado(String usuarioId) => _io('marcar', () async {
    await (await _marcaDesactualizado()).writeAsString(usuarioId, flush: true);
  });

  /// Borra el envoltorio (y el temporal y la marca de desactualizado, si quedaron). Si no había,
  /// no hace nada.
  Future<void> borrar() => _io('borrar', () async {
    final archivo = await _archivo();
    for (final f in [archivo, File('${archivo.path}.tmp'), await _marcaDesactualizado()]) {
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

  /// `existe`, `leer`, `escribir`, `marca`, `marcar` o `borrar`.
  final String operacion;

  final FileSystemException? causa;

  @override
  String toString() => 'ArchivoEnvoltorioException($operacion)';
}

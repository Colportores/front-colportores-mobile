import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../logging/app_logger.dart';
import 'almacen_seguro.dart';

/// Custodia el material secreto con el que se abre la DB local cifrada.
///
/// Guarda **la sal, nunca la clave** (ADR-003, R-AU03): la clave SQLCipher se deriva con Argon2id
/// desde la contraseña del usuario más esta sal y vive solo en memoria volátil mientras la sesión
/// está activa (HU-AUTH-009). Por eso acá no hay ningún método que devuelva una clave: la
/// derivación llega con HU-AUTH-009 (#27) detrás del puerto `ProveedorClaveDb`.
///
/// Las operaciones son primitivas a propósito —no hay un `salOGenerar()` de conveniencia— porque
/// HU-AUTH-009 distingue casos que un atajo taparía: reintentar una inicialización fallida exige
/// **partir desde cero** con una sal nueva, y encontrar la DB sin sal significa tratar el equipo
/// como dispositivo nuevo.
final class CustodiaClaveDb {
  CustodiaClaveDb(this._almacen, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  /// 256 bits (ADR-003, R-AU03).
  static const int bytesDeSal = 32;

  final AlmacenSeguro _almacen;
  final AppLogger _log;
  final Random _aleatorio = Random.secure();

  /// Sal guardada en este dispositivo, o `null` si nunca se generó.
  ///
  /// `null` con el archivo SQLCipher presente significa **dispositivo nuevo**: sin la sal esa DB
  /// ya no se puede abrir (HU-AUTH-009).
  ///
  /// Lanza [SalCorruptaException] si lo guardado no es una sal válida, en lugar de devolver bytes
  /// silenciosamente equivocados que derivarían una clave que no abre nada.
  Future<Uint8List?> leerSal() async {
    final guardada = await _almacen.leer(ClaveSegura.salDb);
    if (guardada == null) return null;
    return _decodificar(guardada);
  }

  /// Genera una sal nueva desde el CSPRNG del sistema operativo y la persiste, **reemplazando la
  /// anterior** (HU-AUTH-009: un reintento no reutiliza la sal del intento fallido).
  ///
  /// Lanza `StateError` si el dispositivo ya está marcado como inicializado: pisar esa sal deja
  /// la DB existente imposible de abrir. Para rehacer el dispositivo desde cero hay que pasar
  /// primero por [olvidar], que es el camino explícito y destructivo.
  Future<Uint8List> generarSal() async {
    if (await dbInicializada()) {
      throw StateError(
        'la DB de este dispositivo ya está inicializada: generar otra sal la dejaría '
        'imposible de abrir. Llamar a olvidar() primero si se quiere rehacer.',
      );
    }

    final sal = Uint8List.fromList(List<int>.generate(bytesDeSal, (_) => _aleatorio.nextInt(256)));
    await _almacen.escribir(ClaveSegura.salDb, base64Encode(sal));
    _log.info(LogModulo.db, 'SAL_GENERADA', 'sal de cifrado generada', {'bytes': bytesDeSal});
    return sal;
  }

  /// Si este dispositivo ya completó la creación de la DB local (HU-AUTH-009).
  Future<bool> dbInicializada() async =>
      await _almacen.leer(ClaveSegura.dbInicializada) == _marcaInicializada;

  /// Marca el dispositivo como inicializado. Se llama **al final** del flujo de HU-AUTH-009, con
  /// la DB ya creada y migrada: antes de eso la marca mentiría sobre una DB a medio hacer.
  Future<void> marcarDbInicializada() async {
    await _almacen.escribir(ClaveSegura.dbInicializada, _marcaInicializada);
    _log.info(LogModulo.db, 'DB_INICIALIZADA', 'dispositivo marcado como inicializado');
  }

  /// Olvida la sal y la marca de inicialización.
  ///
  /// Es **destructivo**: sin la sal, la DB local que quedó en disco no se puede volver a abrir.
  /// Lo usan el borrado de datos (HU-AUTH-010) y la limpieza de una inicialización que quedó a
  /// mitad de camino. Borrar el archivo de la DB es responsabilidad de quien la creó.
  Future<void> olvidar() async {
    await _almacen.borrar(ClaveSegura.salDb);
    await _almacen.borrar(ClaveSegura.dbInicializada);
    _log.warn(LogModulo.db, 'SAL_OLVIDADA', 'sal y marca de inicialización borradas');
  }

  Uint8List _decodificar(String guardada) {
    final Uint8List bytes;
    try {
      bytes = base64Decode(guardada);
    } on FormatException {
      throw const SalCorruptaException('no es base64');
    }

    if (bytes.length != bytesDeSal) {
      throw SalCorruptaException('esperaba $bytesDeSal bytes y tiene ${bytes.length}');
    }
    return bytes;
  }

  static const String _marcaInicializada = 'true';
}

/// Lo guardado como sal no tiene el formato esperado: el almacén se corrompió o alguien escribió
/// esa clave por afuera.
///
/// [toString] describe el motivo pero **nunca** incluye el valor leído.
final class SalCorruptaException implements Exception {
  const SalCorruptaException(this.motivo);

  final String motivo;

  @override
  String toString() => 'SalCorruptaException($motivo)';
}

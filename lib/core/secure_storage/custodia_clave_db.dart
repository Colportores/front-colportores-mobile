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
  ///
  /// Ese `StateError` es un `Error`, no una `Exception`: un `on Exception` no lo atrapa y no
  /// corresponde traducirlo a `Failure`. Significa que el consumidor tomó el camino "dispositivo
  /// nuevo" con la marca puesta, y eso pasa de verdad en iOS: el Keychain sobrevive a la
  /// desinstalación, así que tras reinstalar hay marca y sal pero **no hay archivo de DB**. Ver
  /// [dbInicializada] para lo que tiene que hacer el consumidor antes de llegar acá.
  ///
  /// Propaga [MarcaInicializacionCorruptaException] si la marca no se puede interpretar: la
  /// guarda no se desactiva sola por un valor basura.
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
  ///
  /// Es la marca del almacén seguro, **no** la existencia del archivo SQLCipher, y las dos cosas
  /// se desincronizan en iOS: el Keychain sobrevive a la desinstalación de la app, el archivo no.
  /// Tras reinstalar, esto devuelve `true` con una DB que ya no existe. Quien abra la DB (#6/#27)
  /// tiene que reconciliar marca contra archivo antes de decidir el flujo: marca puesta sin
  /// archivo = llamar a [olvidar] y recién ahí tratar el equipo como dispositivo nuevo. Si se
  /// saltea ese paso, [generarSal] lanza `StateError` en cada intento.
  ///
  /// Lanza [MarcaInicializacionCorruptaException] si lo guardado no es la marca esperada, con la
  /// misma política estricta que [leerSal] aplica a la sal: un valor basura no se interpreta como
  /// "no inicializado", porque eso desactivaría la guarda de [generarSal] y permitiría pisar la
  /// sal de una DB viva. La salida es [olvidar], que no lee la marca.
  Future<bool> dbInicializada() async {
    final guardada = await _almacen.leer(ClaveSegura.dbInicializada);
    if (guardada == null) return false;
    if (guardada == _marcaInicializada) return true;
    throw const MarcaInicializacionCorruptaException('no es la marca esperada');
  }

  /// Marca el dispositivo como inicializado. Se llama **al final** del flujo de HU-AUTH-009, con
  /// la DB ya creada y migrada: antes de eso la marca mentiría sobre una DB a medio hacer.
  Future<void> marcarDbInicializada() async {
    await _almacen.escribir(ClaveSegura.dbInicializada, _marcaInicializada);
    _log.info(LogModulo.db, 'DB_INICIALIZADA', 'dispositivo marcado como inicializado');
  }

  /// Olvida la marca de inicialización y la sal, **en ese orden**.
  ///
  /// Es **destructivo**: sin la sal, la DB local que quedó en disco no se puede volver a abrir.
  /// Lo usan el borrado de datos (HU-AUTH-010) y la limpieza de una inicialización que quedó a
  /// mitad de camino. Borrar el archivo de la DB es responsabilidad de quien la creó.
  ///
  /// El orden importa por si el segundo borrado falla o la app muere entre los dos: queda "sal +
  /// sin marca", que [generarSal] pisa sin problema. Al revés quedaría "sin sal + marca puesta",
  /// y de ahí no se sale: [leerSal] dice dispositivo nuevo y [generarSal] lanza `StateError`.
  Future<void> olvidar() async {
    await _almacen.borrar(ClaveSegura.dbInicializada);
    await _almacen.borrar(ClaveSegura.salDb);
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

/// Lo guardado como marca de inicialización no es la marca esperada: el almacén se corrompió o
/// alguien escribió esa clave por afuera. Misma política que [SalCorruptaException].
///
/// [toString] describe el motivo pero **nunca** incluye el valor leído.
final class MarcaInicializacionCorruptaException implements Exception {
  const MarcaInicializacionCorruptaException(this.motivo);

  final String motivo;

  @override
  String toString() => 'MarcaInicializacionCorruptaException($motivo)';
}

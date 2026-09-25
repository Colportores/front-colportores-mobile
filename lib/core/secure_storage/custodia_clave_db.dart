import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../logging/app_logger.dart';
import 'almacen_seguro.dart';
import 'archivo_envoltorio_dek.dart';
import 'clave_db.dart';
import 'envoltorio_dek.dart';

/// Custodia la DEK de la DB local cifrada y sus dos envoltorios (ADR-006).
///
/// La DB se cifra con una **DEK aleatoria** de 256 bits que nunca se persiste en claro. Se guarda
/// envuelta dos veces:
/// - por el **almacén seguro** del equipo ([AlmacenSeguro], Keystore/Keychain): la app abre la DB
///   sola al arrancar, sin pedir la contraseña;
/// - por **Argon2id(contraseña)**, en un archivo común fuera del almacén ([ArchivoEnvoltorioDek]):
///   viaja con el backup y deja reconstruir el almacén si el Keystore falla.
///
/// Las operaciones son primitivas a propósito —no hay un `dekOGenerar()` de conveniencia— porque
/// HU-AUTH-009 distingue casos que un atajo taparía: reintentar una inicialización fallida exige
/// **partir desde cero** con una DEK nueva, y un almacén que falla con la DB en disco se recupera
/// con la contraseña o se pregunta antes de empezar de nuevo, pero nunca se pisa en silencio.
final class CustodiaClaveDb {
  CustodiaClaveDb(
    this._almacen,
    this._archivo,
    this._proveedorClave,
    this._sellador, {
    this._parametros = ParametrosArgon2id.adr006,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final ArchivoEnvoltorioDek _archivo;
  final ProveedorClaveDb _proveedorClave;
  final SelladorDek _sellador;
  final ParametrosArgon2id _parametros;
  final AppLogger _log;
  final Random _aleatorio = Random.secure();

  // --- DEK en el almacén seguro ---

  /// DEK guardada en el almacén de este equipo, o `null` si no hay ninguna.
  ///
  /// Lanza [DekCorruptaException] si lo guardado no es una DEK válida, en lugar de devolver bytes
  /// equivocados que no abrirían nada, y [AlmacenSeguroException] si el almacén falla.
  Future<ClaveDb?> leerDek() async {
    final guardada = await _almacen.leer(ClaveSegura.dekDb);
    if (guardada == null) return null;

    final Uint8List bytes;
    try {
      bytes = base64Decode(guardada);
    } on FormatException {
      throw const DekCorruptaException('no es base64');
    }
    if (bytes.length != ClaveDb.bytesEsperados) {
      throw DekCorruptaException(
        'esperaba ${ClaveDb.bytesEsperados} bytes y tiene ${bytes.length}',
      );
    }
    return ClaveDb(bytes);
  }

  /// DEK nueva desde el CSPRNG del sistema operativo (HU-AUTH-009). **No** la guarda: eso es
  /// [guardarDek].
  ClaveDb generarDek() => ClaveDb(_bytesAleatorios(ClaveDb.bytesEsperados));

  /// Guarda [dek] en el almacén seguro, **reemplazando la anterior** (HU-AUTH-009: un reintento no
  /// reutiliza la DEK del intento fallido).
  ///
  /// Lanza `StateError` si el dispositivo ya está marcado como inicializado: pisar esa DEK deja la
  /// DB existente imposible de abrir sin la contraseña. Para rehacer el dispositivo desde cero hay
  /// que pasar primero por [olvidar], que es el camino explícito y destructivo; para reconstruir el
  /// almacén con la misma DEK está [reconstruirAlmacen].
  ///
  /// Ese `StateError` es un `Error`, no una `Exception`: un `on Exception` no lo atrapa y no
  /// corresponde traducirlo a `Failure`. Significa que el consumidor tomó el camino "dispositivo
  /// nuevo" con la marca puesta, y eso pasa de verdad en iOS: el Keychain sobrevive a la
  /// desinstalación, así que tras reinstalar hay marca y DEK pero **no hay archivo de DB**. Ver
  /// [dbInicializada] para lo que tiene que hacer el consumidor antes de llegar acá.
  Future<void> guardarDek(ClaveDb dek) async {
    if (await dbInicializada()) {
      throw StateError(
        'la DB de este dispositivo ya está inicializada: otra DEK la dejaría imposible de abrir. '
        'Llamar a olvidar() primero si se quiere rehacer.',
      );
    }
    await _almacen.escribir(ClaveSegura.dekDb, base64Encode(dek.bytes));
    _log.info(LogModulo.db, 'DEK_GUARDADA', 'DEK guardada en el almacén seguro');
  }

  // --- Envoltorio por contraseña ---

  /// Si hay una DEK envuelta con la contraseña en este equipo. No dice si se puede abrir.
  Future<bool> hayEnvoltorioPorPassword() => _archivo.existe();

  /// Envuelve [dek] con Argon2id([password]) y lo guarda en el archivo del envoltorio, reemplazando
  /// el anterior. Usa una sal nueva cada vez y los parámetros de ADR-006, que quedan en la cabecera.
  ///
  /// Tarda de 1 a 2 s (Argon2id corre fuera del isolate de la UI). La clave derivada se destruye al
  /// terminar, salga bien o mal. No toca [dek].
  Future<void> envolverConPassword(ClaveDb dek, String password) async {
    final sal = _bytesAleatorios(EnvoltorioDek.bytesSal);
    final cabecera = EnvoltorioDek.cabeceraDe(
      version: EnvoltorioDek.versionActual,
      algoritmo: EnvoltorioDek.algoritmoActual,
      parametros: _parametros,
      sal: sal,
    );
    final clave = await _proveedorClave.derivar(
      password: password,
      sal: sal,
      parametros: _parametros,
    );
    try {
      final sellado = await _sellador.sellar(dek: dek, clave: clave, cabecera: cabecera);
      await _archivo.escribir(
        EnvoltorioDek(
          version: EnvoltorioDek.versionActual,
          algoritmo: EnvoltorioDek.algoritmoActual,
          parametros: _parametros,
          sal: sal,
          nonce: sellado.nonce,
          cifrado: sellado.cifrado,
        ),
      );
    } finally {
      clave.destruir();
    }
    _log.info(LogModulo.db, 'DEK_ENVUELTA', 'DEK envuelta con la contraseña', {
      'version': EnvoltorioDek.versionActual,
    });
  }

  /// Desenvuelve la DEK con Argon2id([password]) (recuperación guiada de ADR-006). Usa los
  /// parámetros y la sal de la cabecera del envoltorio, no los actuales.
  ///
  /// Lanza [SinEnvoltorioException] si no hay envoltorio, [EnvoltorioCorruptoException] si no se
  /// puede interpretar o es de un algoritmo que esta app no conoce, y [EnvoltorioNoAbreException]
  /// si la contraseña no es la que lo armó.
  Future<ClaveDb> desenvolverConPassword(String password) async {
    final envoltorio = await _archivo.leer();
    if (envoltorio == null) throw const SinEnvoltorioException();
    if (envoltorio.algoritmo != EnvoltorioDek.algoritmoActual) {
      throw const EnvoltorioCorruptoException('algoritmo desconocido');
    }

    final clave = await _proveedorClave.derivar(
      password: password,
      sal: envoltorio.sal,
      parametros: envoltorio.parametros,
    );
    try {
      return await _sellador.abrir(
        nonce: envoltorio.nonce,
        cifrado: envoltorio.cifrado,
        clave: clave,
        cabecera: envoltorio.cabecera,
      );
    } finally {
      clave.destruir();
    }
  }

  // --- Marca de inicialización ---

  /// Si este dispositivo ya completó la creación de la DB local (HU-AUTH-009).
  ///
  /// Es la marca del almacén seguro, **no** la existencia del archivo SQLCipher, y las dos cosas
  /// se desincronizan en iOS: el Keychain sobrevive a la desinstalación de la app, el archivo no.
  /// Tras reinstalar, esto devuelve `true` con una DB que ya no existe. Quien abra la DB tiene que
  /// reconciliar marca contra archivo antes de decidir el flujo: marca puesta sin archivo = llamar
  /// a [olvidar] y recién ahí tratar el equipo como dispositivo nuevo. Si se saltea ese paso,
  /// [guardarDek] lanza `StateError` en cada intento.
  ///
  /// Lanza [MarcaInicializacionCorruptaException] si lo guardado no es la marca esperada: un valor
  /// basura no se interpreta como "no inicializado", porque eso desactivaría la guarda de
  /// [guardarDek] y permitiría pisar la DEK de una DB viva. La salida es [olvidar], que no lee la
  /// marca.
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

  // --- S10 ---

  /// Registra que el usuario aceptó seguir con un Keystore por software (S10, HU-AUTH-009).
  Future<void> registrarConsentimientoAlmacenSoftware() async {
    await _almacen.escribir(ClaveSegura.consentimientoAlmacenSoftware, _aceptado);
    _log.warn(
      LogModulo.db,
      'ALMACEN_SOFTWARE_ACEPTADO',
      'el usuario aceptó el Keystore por software',
    );
  }

  // --- Recuperación y borrado ---

  /// Recuperación guiada de ADR-006: con la DEK ya desenvuelta con la contraseña (y probada contra
  /// la DB), limpia el almacén (`borrarTodo`) y lo reescribe con la marca y esa DEK. Conserva lo
  /// que no es de la DB ([seConservanAlReconstruir]) que se pueda leer. **No** toca el archivo de
  /// la DB ni el envoltorio. No destruye [dek]: sigue siendo de quien la pasó.
  ///
  /// Lo conservado se reescribe **solo si no volvió a aparecer** (#122): entre la lectura y el
  /// final, el refresco automático de Supabase puede guardar una sesión nueva (y adelantar el
  /// reloj), y pisarla con la vieja haría que el servidor detecte un refresh token reutilizado y
  /// cierre la sesión.
  ///
  /// **La marca va antes que la DEK.** Si se corta en el medio queda "marca sin DEK" o nada, y con
  /// la DB en disco los dos llevan a la recuperación guiada. Al revés podría quedar "DEK sin marca",
  /// que el flujo de inicialización toma por una inicialización cortada y descarta: se borraría la
  /// DB del colportor (revisión del PR #81).
  Future<void> reconstruirAlmacen(ClaveDb dek) async {
    final conservados = await _leerConservables();
    await _almacen.borrarTodo();
    await _almacen.escribir(ClaveSegura.dbInicializada, _marcaInicializada);
    await _almacen.escribir(ClaveSegura.dekDb, base64Encode(dek.bytes));
    for (final MapEntry(key: clave, value: valor) in conservados.entries) {
      if (await _almacen.leer(clave) == null) await _almacen.escribir(clave, valor);
    }
    _log.warn(
      LogModulo.db,
      'ALMACEN_RECONSTRUIDO',
      'almacén seguro reescrito con la DEK recuperada',
    );
  }

  /// Lo que [reconstruirAlmacen] vuelve a escribir tal cual: todo lo del almacén que no es de la DB.
  /// El consentimiento de S10 (no se vuelve a preguntar), el último estado de cuenta (HU-AUTH-008:
  /// es lo que usa el gate de la raíz cuando no hay red) y la sesión de HU-AUTH-007: la sesión de
  /// Supabase, el reloj monotónico que mide su ventana y la marca de migrada (sin ella, una copia
  /// vieja de SharedPreferences volvería a migrarse).
  static const Set<ClaveSegura> seConservanAlReconstruir = {
    ClaveSegura.consentimientoAlmacenSoftware,
    ClaveSegura.estadoCuenta,
    ClaveSegura.sesionAuth,
    ClaveSegura.relojSesion,
    ClaveSegura.sesionMigrada,
  };

  /// Los valores de [seConservanAlReconstruir] que se pueden leer. Una clave que el almacén no deja
  /// leer se pierde (nunca se inventa un valor): el consentimiento se vuelve a preguntar y el estado
  /// de cuenta se vuelve a pedir al backend.
  Future<Map<ClaveSegura, String>> _leerConservables() async {
    final conservados = <ClaveSegura, String>{};
    for (final clave in seConservanAlReconstruir) {
      try {
        final valor = await _almacen.leer(clave);
        if (valor != null) conservados[clave] = valor;
      } on AlmacenSeguroException {
        // Ilegible: no se conserva.
      }
    }
    return conservados;
  }

  /// Olvida la marca de inicialización, la DEK del almacén y el consentimiento de S10, **en ese
  /// orden**, y la DEK envuelta con la contraseña.
  ///
  /// Es **destructivo**: sin la DEK, la DB local no se puede volver a abrir. Lo usan el borrado de
  /// datos (HU-AUTH-010), "empezar de nuevo" (ADR-006) y la limpieza de una inicialización que
  /// quedó a mitad de camino, **siempre con el archivo de la DB ya borrado** (borrarlo es de quien
  /// la creó).
  ///
  /// El orden del almacén importa por si un borrado falla o la app muere en el medio: la marca va
  /// primero, así lo que quede es "sin marca", que [guardarDek] pisa sin problema. Al revés quedaría
  /// "sin DEK + marca puesta", y [guardarDek] lanzaría `StateError` en cada intento.
  ///
  /// El envoltorio se borra **aunque el almacén falle** (un Keystore roto no puede dejarlo en
  /// disco): vive fuera del almacén y la DB que cifraba ya no está. Si falla algo, se relanza.
  ///
  /// No toca lo que no es de la DB: "empezar de nuevo" y la limpieza pasan con el usuario adentro.
  /// El borrado de datos (HU-AUTH-010) usa [olvidarDatosDelUsuario].
  Future<void> olvidar() async {
    try {
      for (final clave in seBorranAlOlvidar) {
        await _almacen.borrar(clave);
      }
    } finally {
      await _archivo.borrar();
    }
    _log.warn(LogModulo.db, 'DEK_OLVIDADA', 'DEK, envoltorio y marca de inicialización borrados');
  }

  /// Lo que [olvidar] borra del almacén, **en este orden**: marca, DEK y consentimiento de S10.
  static const List<ClaveSegura> seBorranAlOlvidar = [
    ClaveSegura.dbInicializada,
    ClaveSegura.dekDb,
    ClaveSegura.consentimientoAlmacenSoftware,
  ];

  /// Borrado de datos locales (HU-AUTH-010, #122): [olvidar] y, después, lo que el almacén guarda
  /// del usuario fuera de la DB ([seBorranAlBorrarDatos]). Si algo falla, lanza, y reintentar es
  /// seguro: borrar lo que ya no está no falla.
  ///
  /// Quedan fuera, a propósito ([quedanFueraDelBorradoDeDatos]):
  /// - `sesionAuth`: la borra el cierre de sesión que sigue al borrado (`BorrarDatosLocalesUseCase`).
  ///   Borrarla antes dejaría al usuario adentro en pantalla y afuera al reabrir si ese cierre falla,
  ///   que es justo el caso en que el use case le ofrece reintentar.
  /// - `sesionMigrada`: no tiene datos del usuario, y sin ella una copia vieja de la sesión que haya
  ///   quedado en SharedPreferences se volvería a migrar.
  Future<void> olvidarDatosDelUsuario() async {
    await olvidar();
    for (final clave in seBorranAlBorrarDatos) {
      await _almacen.borrar(clave);
    }
    _log.warn(
      LogModulo.db,
      'DATOS_USUARIO_OLVIDADOS',
      'estado de cuenta y reloj de sesión borrados',
    );
  }

  /// Lo que [olvidarDatosDelUsuario] borra además de lo de [olvidar]: el último estado de cuenta
  /// (lleva el id del usuario) y el reloj de la sesión (el último momento en que se usó la app).
  static const List<ClaveSegura> seBorranAlBorrarDatos = [
    ClaveSegura.estadoCuenta,
    ClaveSegura.relojSesion,
  ];

  /// Lo que el borrado de datos no toca, con el motivo en [olvidarDatosDelUsuario].
  static const List<ClaveSegura> quedanFueraDelBorradoDeDatos = [
    ClaveSegura.sesionAuth,
    ClaveSegura.sesionMigrada,
  ];

  Uint8List _bytesAleatorios(int cantidad) =>
      Uint8List.fromList(List<int>.generate(cantidad, (_) => _aleatorio.nextInt(256)));

  static const String _marcaInicializada = 'true';
  static const String _aceptado = 'true';
}

/// Lo guardado como DEK no tiene el formato esperado: el almacén se corrompió o alguien escribió
/// esa clave por afuera.
///
/// [toString] describe el motivo pero **nunca** incluye el valor leído.
final class DekCorruptaException implements Exception {
  const DekCorruptaException(this.motivo);

  final String motivo;

  @override
  String toString() => 'DekCorruptaException($motivo)';
}

/// Lo guardado como marca de inicialización no es la marca esperada: el almacén se corrompió o
/// alguien escribió esa clave por afuera. Misma política que [DekCorruptaException].
///
/// [toString] describe el motivo pero **nunca** incluye el valor leído.
final class MarcaInicializacionCorruptaException implements Exception {
  const MarcaInicializacionCorruptaException(this.motivo);

  final String motivo;

  @override
  String toString() => 'MarcaInicializacionCorruptaException($motivo)';
}

/// Se pidió desenvolver la DEK con la contraseña y este equipo no tiene envoltorio: el login fue
/// con Google sin backup, o se borró.
final class SinEnvoltorioException implements Exception {
  const SinEnvoltorioException();

  @override
  String toString() => 'SinEnvoltorioException()';
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' show Either, Left, Right, Unit, unit;
import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignInException, GoogleSignInExceptionCode;
import 'package:http/http.dart' as http;

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/entities/estado_respaldo_drive.dart';
import '../../domain/repositories/respaldo_drive_repository.dart';
import '../services/servicio_google.dart';

/// [RespaldoDriveRepository] sobre el almacén seguro (`ClaveSegura.respaldoDrive`) y
/// [ServicioGoogle].
///
/// Guarda por usuario de la app la cuenta de Google y su estado; **ningún token** (ver la clave).
/// Serializa las operaciones: cada una espera a la anterior, así dos cambios seguidos no se pisan
/// y una lectura pedida después de un cambio en vuelo ve lo nuevo. Un valor ilegible (JSON roto)
/// cuenta como «sin conectar»: al conectar se reescribe. Sin correos ni ids de Google en los logs.
final class RespaldoDriveRepositoryImpl implements RespaldoDriveRepository {
  RespaldoDriveRepositoryImpl(
    this._almacen,
    this._google, {
    this.primerRespaldo = const PrimerRespaldoSinMotor(),
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final ServicioGoogle _google;

  /// Hace el primer respaldo al terminar de conectar (hasta #185 no hay motor: no hace nada).
  final PrimerRespaldoDrive primerRespaldo;
  final AppLogger _log;

  Future<void> _cola = Future<void>.value();

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  // --- Almacén: {"<usuario>": {"email": …, "id": …, "estado": …}} ------------------------------

  static const _conectada = 'conectada';
  static const _revocada = 'revocada';
  static const _sinEspacio = 'sin_espacio';

  Future<Map<String, Map<String, String>>> _leerTodo() async {
    final valor = await _almacen.leer(ClaveSegura.respaldoDrive);
    if (valor == null) return {};
    final Object? json;
    try {
      json = jsonDecode(valor);
    } on FormatException {
      return {};
    }
    if (json is! Map<String, dynamic>) return {};
    final todo = <String, Map<String, String>>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (value is! Map<String, dynamic>) continue;
      final email = value['email'];
      final id = value['id'];
      final estado = value['estado'];
      if (email is String && id is String && estado is String && email.isNotEmpty) {
        todo[key] = {'email': email, 'id': id, 'estado': estado};
      }
    }
    return todo;
  }

  /// Lo guardado, o nada si no se deja leer: al conectar o desconectar, lo ilegible se pisa.
  Future<Map<String, Map<String, String>>> _leerTodoOVacio() async {
    try {
      return await _leerTodo();
    } on Object {
      return {};
    }
  }

  Future<void> _escribirTodo(Map<String, Map<String, String>> todo) async {
    if (todo.isEmpty) {
      await _almacen.borrar(ClaveSegura.respaldoDrive);
    } else {
      await _almacen.escribir(ClaveSegura.respaldoDrive, jsonEncode(todo));
    }
  }

  EstadoRespaldoDrive _aEstado(Map<String, String>? fila) {
    if (fila == null) return const DriveSinConectar();
    final email = fila['email']!;
    final id = fila['id']!;
    return switch (fila['estado']) {
      _revocada => DrivePermisoRevocado(email: email, cuentaId: id),
      _sinEspacio => DriveSinEspacio(email: email, cuentaId: id),
      _ => DriveConectada(email: email, cuentaId: id),
    };
  }

  Failure _falloDelAlmacen(String operacion, Object error) {
    _log.warn(LogModulo.backup, 'DRIVE_ALMACEN', 'no se pudo usar el almacén del respaldo', {
      'operacion': operacion,
      'error': error.runtimeType.toString(),
    });
    return const FailureAlmacenSeguro();
  }

  // --- RespaldoDriveRepository ------------------------------------------------------------------

  @override
  Future<Either<Failure, EstadoRespaldoDrive>> estado(String usuarioId) => _encolar(() async {
    try {
      return Right(_aEstado((await _leerTodo())[usuarioId]));
    } on Object catch (e) {
      return Left(_falloDelAlmacen('leer', e));
    }
  });

  @override
  Future<Either<Failure, ConexionDrive>> conectar(String usuarioId) => _encolar(() async {
    final CuentaGoogle cuenta;
    try {
      cuenta = await _google.conectar();
    } on Object catch (e) {
      return Left(_traducirFalloDeGoogle(e));
    }

    final conectada = DriveConectada(email: cuenta.email, cuentaId: cuenta.id);
    try {
      final todo = await _leerTodoOVacio();
      todo[usuarioId] = {'email': cuenta.email, 'id': cuenta.id, 'estado': _conectada};
      await _escribirTodo(todo);
    } on Object catch (e) {
      // Google ya dio el permiso pero la app no pudo anotarlo: se lo retira para no dejar un
      // permiso suelto que la app no recuerda.
      await _retirarPermiso();
      return Left(_falloDelAlmacen('escribir', e));
    }

    _log.info(LogModulo.backup, 'DRIVE_CONECTADO', 'respaldo en Drive conectado');
    final primero = await _hacerPrimerRespaldo();
    return Right(ConexionDrive(estado: conectada, primerRespaldoHecho: primero));
  });

  Future<bool> _hacerPrimerRespaldo() async {
    try {
      return await primerRespaldo.hacer();
    } on Object catch (e) {
      _log.warn(LogModulo.backup, 'DRIVE_PRIMER_RESPALDO', 'el primer respaldo no salió', {
        'error': e.runtimeType.toString(),
      });
      return false;
    }
  }

  /// Le pide a Google que retire el permiso; es de mejor esfuerzo.
  Future<void> _retirarPermiso() async {
    try {
      await _google.desconectar();
    } on Object catch (e) {
      _log.warn(LogModulo.backup, 'DRIVE_REVOCAR', 'no se pudo retirar el permiso en Google', {
        'error': e.runtimeType.toString(),
      });
    }
  }

  /// Qué le pasa a la persona según lo que dijo el plugin. La causa va a los logs, sin datos.
  Failure _traducirFalloDeGoogle(Object error) {
    if (_esDeRed(error)) return const FailureSinConexion();
    if (error is PermisoDriveNoConcedido) return const FailureDrivePermisoIncompleto();
    if (error is GoogleSignInException) {
      if (error.code == GoogleSignInExceptionCode.canceled) return const FailureDriveCancelado();
      _log.warn(LogModulo.backup, 'DRIVE_GOOGLE', 'Google no pudo conectar el respaldo', {
        'codigo': error.code.name,
      });
      return const FailureDriveNoConectado();
    }
    _log.warn(LogModulo.backup, 'DRIVE_GOOGLE', 'falló la conexión del respaldo', {
      'error': error.runtimeType.toString(),
    });
    return const FailureDriveNoConectado();
  }

  bool _esDeRed(Object error) =>
      error is SocketException || error is http.ClientException || error is TimeoutException;

  @override
  Future<Either<Failure, Unit>> desconectar(String usuarioId) => _encolar(() async {
    try {
      final todo = await _leerTodoOVacio();
      // Aunque no hubiera entrada se reescribe: una clave ilegible se limpia.
      todo.remove(usuarioId);
      await _escribirTodo(todo);
    } on Object catch (e) {
      return Left(_falloDelAlmacen('borrar', e));
    }
    _log.info(LogModulo.backup, 'DRIVE_DESCONECTADO', 'respaldo en Drive desconectado');
    await _retirarPermiso();
    return const Right(unit);
  });

  @override
  Future<void> retirarPermisoGoogle() => _encolar(_retirarPermiso);

  Future<Either<Failure, EstadoRespaldoDrive>> _cambiarEstado(
    String usuarioId,
    String nuevo, {
    String? soloDesde,
    String? cuentaId,
  }) => _encolar(() async {
    try {
      final todo = await _leerTodo();
      final fila = todo[usuarioId];
      if (fila == null) return const Right(DriveSinConectar());
      if (fila['estado'] == nuevo ||
          (soloDesde != null && fila['estado'] != soloDesde) ||
          (cuentaId != null && fila['id'] != cuentaId)) {
        return Right(_aEstado(fila));
      }
      final cambiada = {...fila, 'estado': nuevo};
      todo[usuarioId] = cambiada;
      await _escribirTodo(todo);
      return Right(_aEstado(cambiada));
    } on Object catch (e) {
      return Left(_falloDelAlmacen('escribir', e));
    }
  });

  @override
  Future<Either<Failure, EstadoRespaldoDrive>> marcarPermisoRevocado(
    String usuarioId, {
    String? cuentaId,
  }) => _cambiarEstado(usuarioId, _revocada, cuentaId: cuentaId);

  @override
  Future<Either<Failure, EstadoRespaldoDrive>> marcarSinEspacio(String usuarioId) =>
      _cambiarEstado(usuarioId, _sinEspacio, soloDesde: _conectada);

  @override
  Future<Either<Failure, EstadoRespaldoDrive>> marcarRespaldoGuardado(String usuarioId) =>
      _cambiarEstado(usuarioId, _conectada, soloDesde: _sinEspacio);

  @override
  Future<Either<Failure, EstadoRespaldoDrive>> verificarPermiso(String usuarioId) async {
    final actual = await estado(usuarioId);
    final estadoActual = actual.fold<EstadoRespaldoDrive?>((_) => null, (e) => e);
    // Solo se mira donde el permiso se supone vigente: ni sin cuenta, ni ya revocado.
    if (estadoActual is! DriveConectada && estadoActual is! DriveSinEspacio) return actual;
    final cuentaId = (estadoActual as DriveConCuenta).cuentaId;
    final String? token;
    try {
      token = await _google.tokenSilencioso();
    } on Object catch (e) {
      // Sin red o con Google caído no se concluye que el permiso se perdió.
      _log.info(LogModulo.backup, 'DRIVE_VERIFICAR', 'no se pudo ver el permiso de Drive', {
        'error': e.runtimeType.toString(),
      });
      return estado(usuarioId);
    }
    // El token pudo tardar: la persona pudo desconectar o conectar otra cuenta mientras tanto. Se
    // devuelve lo que hay ahora, no lo que había al empezar, y solo se marca la cuenta que se miró.
    if (token != null) return estado(usuarioId);
    _log.warn(LogModulo.backup, 'DRIVE_REVOCADO', 'Google ya no tiene el permiso de Drive');
    return marcarPermisoRevocado(usuarioId, cuentaId: cuentaId);
  }

  @override
  Future<String?> tokenDeAcceso(String usuarioId) async {
    final actual = await estado(usuarioId);
    final estadoActual = actual.fold<EstadoRespaldoDrive?>((_) => null, (e) => e);
    if (estadoActual is! DriveConectada && estadoActual is! DriveSinEspacio) return null;
    final cuentaId = (estadoActual as DriveConCuenta).cuentaId;
    try {
      final token = await _google.tokenSilencioso();
      if (token == null) await marcarPermisoRevocado(usuarioId, cuentaId: cuentaId);
      return token;
    } on Object catch (e) {
      _log.info(LogModulo.backup, 'DRIVE_TOKEN', 'no se pudo pedir el token de Drive', {
        'error': e.runtimeType.toString(),
      });
      return null;
    }
  }
}

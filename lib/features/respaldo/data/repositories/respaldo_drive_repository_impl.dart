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
///
/// Anota también **cuándo se conectó** cada cuenta (`conectado_en`, #583): sin ningún respaldo, los
/// días «sin respaldo» se cuentan desde ahí.
///
/// Si al conectar Google devuelve una cuenta distinta de la que ya tenía el respaldo (16E·01), la fila
/// queda `por_confirmar` con la cuenta anterior (`anterior_email`, `anterior_id`) hasta que la persona
/// elija: ahí el respaldo está frenado. Si oculta la franja del Drive de Hoy (16F·04), el día queda en
/// `franja_oculta`; cualquier cambio de estado la vuelve a mostrar.
final class RespaldoDriveRepositoryImpl implements RespaldoDriveRepository {
  RespaldoDriveRepositoryImpl(
    this._almacen,
    this._google, {
    this.primerRespaldo = const PrimerRespaldoSinMotor(),
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? (() => DateTime.now().toUtc()),
       _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final ServicioGoogle _google;

  /// Hace el primer respaldo al terminar de conectar (hasta #185 no hay motor: no hace nada).
  final PrimerRespaldoDrive primerRespaldo;
  final DateTime Function() _ahora;
  final AppLogger _log;

  Future<void> _cola = Future<void>.value();

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  // --- Almacén: {"<usuario>": {"email": …, "id": …, "estado": …, "conectado_en": …}} ----------

  static const _conectada = 'conectada';
  static const _revocada = 'revocada';
  static const _sinEspacio = 'sin_espacio';
  static const _conectadoEn = 'conectado_en';
  static const _porConfirmar = 'por_confirmar';
  static const _anteriorEmail = 'anterior_email';
  static const _anteriorId = 'anterior_id';
  static const _franjaOculta = 'franja_oculta';
  static const _camposOpcionales = [_conectadoEn, _anteriorEmail, _anteriorId, _franjaOculta];

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
        todo[key] = {
          'email': email,
          'id': id,
          'estado': estado,
          for (final campo in _camposOpcionales)
            if (value[campo] case final String texto) campo: texto,
        };
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
    final anteriorEmail = fila[_anteriorEmail];
    final anteriorId = fila[_anteriorId];
    return switch (fila['estado']) {
      _porConfirmar when anteriorEmail != null && anteriorId != null => DriveCuentaPorConfirmar(
        email: email,
        cuentaId: id,
        anteriorEmail: anteriorEmail,
        anteriorCuentaId: anteriorId,
      ),
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
  Future<DateTime?> conectadaDesde(String usuarioId) => _encolar(() async {
    try {
      final todo = await _leerTodo();
      final fila = todo[usuarioId];
      if (fila == null) return null;
      final guardada = DateTime.tryParse(fila[_conectadoEn] ?? '');
      if (guardada != null) return guardada.toUtc();
      // Una cuenta conectada antes de que se anotara la fecha: lo único que se sabe es que lo está
      // ahora. Se anota hoy y se cuenta desde hoy; no se inventa una fecha anterior.
      final ahora = _ahora().toUtc();
      todo[usuarioId] = {...fila, _conectadoEn: ahora.toIso8601String()};
      await _escribirTodo(todo);
      return ahora;
    } on Object catch (e) {
      _falloDelAlmacen('leer', e);
      return null;
    }
  });

  @override
  Future<Either<Failure, ConexionDrive>> conectar(
    String usuarioId, {
    bool conPrimerRespaldo = true,
  }) => _encolar(() async {
    final CuentaGoogle cuenta;
    try {
      cuenta = await _google.conectar();
    } on Object catch (e) {
      return Left(_traducirFalloDeGoogle(e));
    }

    final DriveConCuenta conectada;
    var volvioDeOtraCuenta = false;
    try {
      final todo = await _leerTodoOVacio();
      // La cuenta de referencia es la del respaldo anterior: si ya había otra por confirmar, sigue
      // siendo la que tenía el respaldo antes de ella.
      final previa = todo[usuarioId];
      final anteriorId = previa?[_anteriorId] ?? previa?['id'];
      final anteriorEmail = previa?[_anteriorEmail] ?? previa?['email'];
      // Para recuperar (conPrimerRespaldo en `false`, #707) la cuenta que elige es la que quiere
      // buscar: no se compara con la del respaldo anterior.
      final otra =
          conPrimerRespaldo &&
              anteriorId != null &&
              anteriorEmail != null &&
              anteriorId != cuenta.id
          ? DriveCuentaPorConfirmar(
              email: cuenta.email,
              cuentaId: cuenta.id,
              anteriorEmail: anteriorEmail,
              anteriorCuentaId: anteriorId,
            )
          : null;
      volvioDeOtraCuenta = previa?[_anteriorId] != null && otra == null;
      conectada = otra ?? DriveConectada(email: cuenta.email, cuentaId: cuenta.id);
      todo[usuarioId] = {
        'email': cuenta.email,
        'id': cuenta.id,
        'estado': otra == null ? _conectada : _porConfirmar,
        if (otra != null) _anteriorEmail: otra.anteriorEmail,
        if (otra != null) _anteriorId: otra.anteriorCuentaId,
        _conectadoEn: _ahora().toUtc().toIso8601String(),
      };
      await _escribirTodo(todo);
    } on Object catch (e) {
      // Google ya dio el permiso pero la app no pudo anotarlo: se lo retira para no dejar un
      // permiso suelto que la app no recuerda.
      await _retirarPermiso();
      // La causa va al log (sin datos). A la persona se le dice lo mismo que en cualquier otra falla
      // de la conexión, no el aviso del almacén de la base de datos, que habla de reinstalar la app.
      _falloDelAlmacen('escribir', e);
      return const Left(FailureDriveNoConectado());
    }

    _log.info(
      LogModulo.backup,
      conectada is DriveCuentaPorConfirmar ? 'DRIVE_OTRA_CUENTA' : 'DRIVE_CONECTADO',
      conectada is DriveCuentaPorConfirmar
          ? 'se conectó otra cuenta de Google: falta elegir con cuál seguir'
          : 'respaldo en Drive conectado',
    );
    // Con otra cuenta por confirmar no se sube nada: el primer respaldo espera a la elección. Al
    // volver a la cuenta anterior tampoco: su respaldo sigue ahí. Para recuperar (#707) no se sube
    // el teléfono vacío: el asistente cuenta solo los viejos.
    final primero =
        conPrimerRespaldo &&
        conectada is DriveConectada &&
        !volvioDeOtraCuenta &&
        await _hacerPrimerRespaldo();
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
  Future<Either<Failure, ConexionDrive>> confirmarCuentaNueva(
    String usuarioId, {
    bool conPrimerRespaldo = true,
  }) async {
    final anotada = await _encolar<Either<Failure, (DriveConCuenta, bool)>>(() async {
      try {
        final todo = await _leerTodo();
        final fila = todo[usuarioId];
        if (fila == null) return const Left(FailureDriveNoConectado());
        final estado = _aEstado(fila);
        if (estado is! DriveCuentaPorConfirmar) {
          return estado is DriveConCuenta
              ? Right((estado, false))
              : const Left(FailureDriveNoConectado());
        }
        final elegida = {
          'email': fila['email']!,
          'id': fila['id']!,
          'estado': _conectada,
          if (fila[_conectadoEn] case final String desde) _conectadoEn: desde,
        };
        todo[usuarioId] = elegida;
        await _escribirTodo(todo);
        _log.info(LogModulo.backup, 'DRIVE_CUENTA_NUEVA', 'se siguió con la cuenta nueva');
        return Right((_aEstado(elegida) as DriveConCuenta, true));
      } on Object catch (e) {
        // Como al conectar: a la persona se le dice lo de siempre, no el aviso del almacén de la base
        // de datos (que habla de reinstalar la app). La causa va al log.
        _falloDelAlmacen('escribir', e);
        return const Left(FailureDriveNoConectado());
      }
    });
    // Fuera de la cola: el primer respaldo vuelve a leer el estado de este mismo repositorio.
    return anotada.fold<Future<Either<Failure, ConexionDrive>>>(
      (falla) async => Left(falla),
      (anotado) async => Right(
        ConexionDrive(
          estado: anotado.$1,
          primerRespaldoHecho: conPrimerRespaldo && anotado.$2 && await _hacerPrimerRespaldo(),
        ),
      ),
    );
  }

  @override
  Future<Either<Failure, Unit>> ocultarFranja(String usuarioId) => _encolar(() async {
    try {
      final todo = await _leerTodo();
      final fila = todo[usuarioId];
      if (fila == null) return const Right(unit);
      todo[usuarioId] = {...fila, _franjaOculta: _dia(_ahora())};
      await _escribirTodo(todo);
      return const Right(unit);
    } on Object catch (e) {
      return Left(_falloDelAlmacen('escribir', e));
    }
  });

  @override
  Future<DateTime?> franjaOcultaEl(String usuarioId) => _encolar(() async {
    try {
      final guardado = (await _leerTodo())[usuarioId]?[_franjaOculta];
      if (guardado == null) return null;
      final dia = DateTime.tryParse(guardado);
      return dia == null ? null : DateTime(dia.year, dia.month, dia.day);
    } on Object catch (e) {
      _falloDelAlmacen('leer', e);
      return null;
    }
  });

  /// El día de [instante] en la hora del teléfono, como `AAAA-MM-DD`.
  String _dia(DateTime instante) {
    final local = instante.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

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
          // Con otra cuenta por confirmar el respaldo está frenado: no hay permiso que perder ni
          // espacio que llenar hasta que la persona elija.
          fila['estado'] == _porConfirmar ||
          (soloDesde != null && fila['estado'] != soloDesde) ||
          (cuentaId != null && fila['id'] != cuentaId)) {
        return Right(_aEstado(fila));
      }
      // Cambia el estado: la franja oculta de Hoy vuelve a salir (16F·04).
      final cambiada = {...fila, 'estado': nuevo}..remove(_franjaOculta);
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

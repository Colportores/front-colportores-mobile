import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/estado_db_local.dart';
import '../repositories/db_local_repository.dart';
import '../repositories/vigencia_sesion.dart';

/// Pasos que la UI muestra como progreso ("Preparando tu espacio seguro… 1/3, 2/3, 3/3",
/// HU-AUTH-009). En un login posterior no hay [generandoSal]: la sal ya existe.
enum PasoInicializacionDb { generandoSal, derivandoClave, abriendoDb }

/// Cómo terminó una inicialización exitosa.
enum ResultadoInicializacionDb {
  /// Primer login en el dispositivo (o dispositivo tratado como nuevo): la DB se creó de cero.
  creada,

  /// Login posterior: se abrió la DB que ya estaba.
  abierta,
}

/// Parámetros de [InicializarDbLocalUseCase].
final class InicializarDbLocalParams extends Equatable {
  const InicializarDbLocalParams({required this.password, this.alAvanzar});

  /// Contraseña con la que el usuario acaba de autenticarse: de ella se deriva la clave (ADR-003).
  final String password;

  /// Avisa cada [PasoInicializacionDb] al empezarlo. Se llama en forma sincrónica.
  final void Function(PasoInicializacionDb paso)? alAvanzar;

  /// [props] lleva la contraseña en texto plano: sin esto, interpolar los params en un log la
  /// filtraría (convenciones-desarrollo.md §7.5), igual que en `IniciarSesionParams`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [password, alAvanzar];
}

/// HU-AUTH-009 — Inicialización de la DB local cifrada tras un login con contraseña.
///
/// **Primer login** (o dispositivo que hay que tratar como nuevo): deja el dispositivo limpio,
/// genera y guarda una sal nueva, deriva la clave, crea la DB y recién al final marca el
/// dispositivo como inicializado. Si algo falla en el camino, vuelve a dejarlo limpio: nunca queda
/// una DB a medio hacer ni una sal suelta, y el próximo intento parte desde cero con otra sal.
///
/// **Login posterior** (marca puesta, archivo presente y sal guardada): lee la sal, deriva y abre.
/// Si algo falla **no se borra nada**: la DB tiene datos del usuario.
///
/// Se trata como nuevo, según HU-AUTH-009 y la custodia de la sal:
/// - sin marca de inicialización (primer login, o una inicialización interrumpida que dejó sal o
///   archivo sueltos);
/// - marca sin archivo (iOS: el Keychain sobrevive a la desinstalación, el archivo no);
/// - archivo sin sal (sin la sal esa DB ya no se puede abrir).
///
/// ## Cierre de sesión durante la derivación
///
/// Después de derivar y **inmediatamente antes de abrir** vuelve a verificar que la sesión sigue
/// vigente. Si no, destruye la clave y no abre: si abriera, la DB quedaría abierta sin sesión,
/// porque el cierre ya pasó y no tiene nada que cerrar (revisión del PR #44). Entre ese chequeo y
/// la apertura no puede haber ningún `await`.
///
/// La derivación (Argon2id) está detrás de [DbLocalRepository.derivarClave]; este caso de uso no
/// sabe con qué librería ni con qué parámetros se deriva.
///
/// Se llama una vez por sesión, con la DB cerrada. Llamarlo con la DB ya abierta es un error del
/// llamador y sale como el `StateError` de `DatabaseHelper.abrir`, sin traducir a [Failure].
final class InicializarDbLocalUseCase
    implements UseCase<ResultadoInicializacionDb, InicializarDbLocalParams> {
  const InicializarDbLocalUseCase(this._repository, this._vigencia);

  final DbLocalRepository _repository;
  final VigenciaSesion _vigencia;

  @override
  Future<Either<Failure, ResultadoInicializacionDb>> call(InicializarDbLocalParams params) async {
    if (params.password.isEmpty) {
      return const Left(FailureValidacion(campos: {'password': 'Ingresá tu contraseña'}));
    }

    // Antes de cualquier otra cosa: un cierre de sesión que llegue desde acá invalida el testigo.
    final testigo = _vigencia.tomarTestigo();
    if (testigo == null) return const Left(FailureSesionCerrada());

    final estado = await _repository.estado();
    if (estado case Left(value: final falla)) return Left(falla);

    if (estado._valor case EstadoDbLocal(inicializada: true, archivoExiste: true)) {
      final sal = await _repository.leerSal();
      if (sal case Left(value: final falla)) return Left(falla);
      final guardada = sal._valor;
      if (guardada != null) return _abrirExistente(params, testigo, guardada);
    }
    return _crearDesdeCero(params, testigo);
  }

  Future<Either<Failure, ResultadoInicializacionDb>> _abrirExistente(
    InicializarDbLocalParams params,
    TestigoSesion testigo,
    Uint8List sal,
  ) async {
    params.alAvanzar?.call(PasoInicializacionDb.derivandoClave);
    final clave = await _repository.derivarClave(password: params.password, sal: sal);
    if (clave case Left(value: final falla)) return Left(falla);

    params.alAvanzar?.call(PasoInicializacionDb.abriendoDb);
    final abierta = await _abrirSiSigueVigente(clave._valor, testigo);
    return abierta.map((_) => ResultadoInicializacionDb.abierta);
  }

  Future<Either<Failure, ResultadoInicializacionDb>> _crearDesdeCero(
    InicializarDbLocalParams params,
    TestigoSesion testigo,
  ) async {
    // Si no se pudo limpiar no se sigue: una sal nueva contra un archivo viejo no lo abriría.
    final limpio = await _repository.descartar();
    if (limpio case Left(value: final falla)) return Left(falla);

    params.alAvanzar?.call(PasoInicializacionDb.generandoSal);
    final sal = await _repository.generarSal();
    if (sal case Left(value: final falla)) return _abortar(falla);

    params.alAvanzar?.call(PasoInicializacionDb.derivandoClave);
    final clave = await _repository.derivarClave(password: params.password, sal: sal._valor);
    if (clave case Left(value: final falla)) return _abortar(falla);

    params.alAvanzar?.call(PasoInicializacionDb.abriendoDb);
    final abierta = await _abrirSiSigueVigente(clave._valor, testigo);
    if (abierta case Left(value: final falla)) return _abortar(falla);

    final marcada = await _repository.marcarInicializada();
    if (marcada case Left(value: final falla)) return _abortar(falla);

    return const Right(ResultadoInicializacionDb.creada);
  }

  /// Sin `async` a propósito: entre el chequeo del testigo y el pedido de apertura no hay ningún
  /// `await`, así que un cierre de sesión no puede quedar en el medio. O llegó antes (y acá se ve),
  /// o llega después, con la apertura ya registrada, y la cierra.
  Future<Either<Failure, Unit>> _abrirSiSigueVigente(ClaveDb clave, TestigoSesion testigo) {
    if (!testigo.sigueVigente) {
      clave.destruir();
      return Future.value(const Left(FailureSesionCerrada()));
    }
    return _repository.abrir(clave);
  }

  /// Deja el dispositivo limpio tras un primer login fallido y devuelve la falla original. Si la
  /// limpieza también falla, igual se devuelve la original (es la que explica qué pasó); lo que
  /// quede suelto lo limpia el próximo intento, que por no tener marca vuelve a pasar por acá.
  Future<Either<Failure, ResultadoInicializacionDb>> _abortar(Failure falla) async {
    await _repository.descartar();
    return Left(falla);
  }
}

extension _Derecha<T> on Either<Failure, T> {
  /// Valor de un `Right`. Solo después de haber descartado el `Left`.
  T get _valor => (this as Right<Failure, T>).value;
}

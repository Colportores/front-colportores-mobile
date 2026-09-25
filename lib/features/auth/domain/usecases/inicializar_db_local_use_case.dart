import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/dispositivo/seguridad_dispositivo.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/estado_db_local.dart';
import '../repositories/db_local_repository.dart';
import '../repositories/vigencia_sesion.dart';
import '../services/turno_db_local.dart';

/// Pasos que la UI muestra como progreso ("Preparando tu espacio seguro… 1/3, 2/3, 3/3",
/// HU-AUTH-009). Al crear la DB son los tres, salvo [protegiendoClave] sin contraseña (login con
/// Google); al abrir una DB existente, [abriendoDb], antecedido por [protegiendoClave] si hay que
/// armar el envoltorio.
enum PasoInicializacionDb {
  /// Genera la DEK y la guarda en el almacén seguro.
  generandoClave,

  /// Envuelve la DEK con Argon2id(contraseña): el paso largo, de 1 a 2 s.
  protegiendoClave,

  /// Crea (o abre) el archivo SQLCipher y aplica el esquema.
  abriendoDb,
}

/// Cómo terminó una inicialización exitosa.
enum ResultadoInicializacionDb {
  /// Primer login en el dispositivo (o dispositivo tratado como nuevo): la DB se creó de cero.
  creada,

  /// Ya estaba: se abrió con la DEK del almacén seguro.
  abierta,
}

/// Parámetros de [InicializarDbLocalUseCase].
final class InicializarDbLocalParams extends Equatable {
  const InicializarDbLocalParams({
    this.password,
    this.requiereEnvoltorio = false,
    this.aceptaAlmacenSoftware = false,
    this.alAvanzar,
  });

  /// Contraseña con la que el usuario acaba de autenticarse, o `null` si no hay (login con Google,
  /// sesión restaurada). Solo se usa al crear la DB, para envolver la DEK (ADR-006): sin ella no hay
  /// envoltorio por contraseña.
  final String? password;

  /// La cuenta entra con contraseña, así que la DB tiene que quedar con envoltorio (ADR-006). Sin
  /// [password], no se crea la DB ni se da por lista una que no lo tiene: devuelve
  /// [FailurePasswordParaProteger] sin tocar nada, y la UI pide la contraseña (revisión del PR
  /// #130).
  final bool requiereEnvoltorio;

  /// El usuario ya aceptó seguir con un Keystore por software (S10): la UI lo pasa en `true`
  /// después de mostrar [FailureAlmacenPocoSeguro] y recibir "Entiendo el riesgo y quiero
  /// continuar".
  final bool aceptaAlmacenSoftware;

  /// Avisa cada [PasoInicializacionDb] al empezarlo. Se llama en forma sincrónica.
  final void Function(PasoInicializacionDb paso)? alAvanzar;

  /// [props] lleva la contraseña en texto plano: sin esto, interpolar los params en un log la
  /// filtraría (convenciones-desarrollo.md §7.5), igual que en `IniciarSesionParams`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [password, requiereEnvoltorio, aceptaAlmacenSoftware, alAvanzar];
}

/// HU-AUTH-009 — Inicialización de la DB local cifrada con una DEK aleatoria envuelta (ADR-006).
///
/// Se llama después de cada login y al restaurar la sesión, con la DB cerrada.
///
/// **DB existente** (marca puesta y archivo en disco): lee la DEK del almacén seguro y abre, sin
/// Argon2id y sin contraseña. Si algo falla **no se borra nada**: la DB tiene datos del usuario.
/// Si el login fue con contraseña y el equipo no tiene envoltorio (entró con Google, o se perdió),
/// lo arma antes de abrir; si eso falla, abre igual.
/// Si el almacén falla o perdió la DEK rige la recuperación guiada: con envoltorio por contraseña,
/// [FailureAlmacenSeguroRecuperable] (sigue `RecuperarDbLocalConPasswordUseCase`); sin él,
/// [FailureAlmacenSeguroSinRecuperacion] (la UI ofrece "empezar de nuevo" y pregunta).
///
/// **Primer login** (o dispositivo que hay que tratar como nuevo):
/// 1. Verifica el bloqueo de pantalla; sin él no sigue ([FailureSinBloqueoPantalla]).
/// 2. Mira el nivel del Keystore; por software y sin consentimiento, no sigue
///    ([FailureAlmacenPocoSeguro]). Con consentimiento lo registra.
/// 3. Deja el dispositivo limpio, genera la DEK y la guarda en el almacén seguro.
/// 4. Si hay contraseña, envuelve la DEK con Argon2id(contraseña).
/// 5. Crea la DB con la DEK y recién al final marca el dispositivo como inicializado.
///
/// Si algo falla desde el paso 3, vuelve a dejarlo limpio: nunca queda una DB a medio hacer ni una
/// DEK suelta, y el próximo intento parte desde cero con otra DEK.
///
/// Se trata como nuevo:
/// - sin archivo, haya marca o no (primer login; o iOS, donde el Keychain sobrevive a la
///   desinstalación y el archivo no);
/// - archivo sin marca pero con la DEK en el almacén: una inicialización que se cortó (la marca va
///   última, así que esa DB nunca se usó).
///
/// Archivo sin marca y **sin** DEK no es una inicialización cortada (la DEK se guarda antes de
/// crear el archivo): es un almacén que perdió todo con la DB en disco, y rige la recuperación
/// guiada. Nunca se borra una DB que pueda tener datos.
///
/// ## Un flujo a la vez
///
/// Corre dentro de [TurnoDbLocal], compartido con la recuperación y "empezar de nuevo": dos flujos
/// en paralelo se pisarían la DEK (revisión del PR #81). El segundo espera y, cuando le toca, ve el
/// estado que dejó el primero: si la DB ya quedó abierta, devuelve
/// [ResultadoInicializacionDb.abierta] sin tocar nada.
///
/// ## Cierre de sesión en el medio
///
/// Inmediatamente antes de abrir vuelve a verificar que la sesión sigue vigente
/// ([AperturaConSesionVigente.abrirSiSigueVigente]). Si no, destruye la DEK y no abre (revisión del
/// PR #44); al crear, además deja el dispositivo limpio. El testigo se toma al llamar, antes de
/// esperar el turno.
final class InicializarDbLocalUseCase
    implements UseCase<ResultadoInicializacionDb, InicializarDbLocalParams> {
  const InicializarDbLocalUseCase(this._repository, this._vigencia, this._turno);

  final DbLocalRepository _repository;
  final VigenciaSesion _vigencia;
  final TurnoDbLocal _turno;

  @override
  Future<Either<Failure, ResultadoInicializacionDb>> call(InicializarDbLocalParams params) async {
    if (params.password case '') {
      return const Left(FailureValidacion(campos: {'password': 'Ingresá tu contraseña'}));
    }

    // Antes de cualquier otra cosa: un cierre de sesión que llegue desde acá invalida el testigo.
    final testigo = _vigencia.tomarTestigo();
    if (testigo == null) return const Left(FailureSesionCerrada());

    return _turno.enExclusiva(() => _inicializar(params, testigo));
  }

  Future<Either<Failure, ResultadoInicializacionDb>> _inicializar(
    InicializarDbLocalParams params,
    TestigoSesion testigo,
  ) async {
    final estado = await _repository.estado();
    if (estado case Left(value: final falla)) return Left(falla);

    final e = estado._valor;
    // Otro flujo ya la abrió mientras este esperaba el turno: no hay nada que hacer.
    if (e.abierta) return const Right(ResultadoInicializacionDb.abierta);
    if (e.archivoExiste) {
      switch (e.marca) {
        case MarcaDbLocal.puesta:
          return _abrirExistente(params, testigo, e);
        case MarcaDbLocal.ilegible:
          // Con la DB en disco y un almacén que no responde no se sabe si hay datos: nunca se crea
          // encima.
          return Left(_sinDek(e));
        case MarcaDbLocal.ausente:
          final interrumpida = await _esInicializacionInterrumpida(e);
          if (interrumpida case Left(value: final falla)) return Left(falla);
      }
    }
    return _crearDesdeCero(params, testigo);
  }

  /// Archivo sin marca: ¿una inicialización que se cortó, o un almacén que perdió todo con la DB
  /// en disco?
  ///
  /// La DEK se guarda **antes** de que exista el archivo, así que una inicialización cortada deja
  /// la DEK en el almacén: esa DB nunca se usó (la marca va última) y se descarta, como pide
  /// HU-AUTH-009. Sin DEK es el otro caso —por ejemplo, un iPhone restaurado de un backup trae los
  /// archivos pero no el Keychain (`_ThisDeviceOnly`)—, y la DB puede tener datos: rige la
  /// recuperación guiada y no se borra nada. `Right` = seguir creando de cero.
  Future<Either<Failure, Unit>> _esInicializacionInterrumpida(EstadoDbLocal estado) async {
    final leida = await _repository.leerDek();
    if (leida case Right(value: final ClaveDb dek)) {
      dek.destruir();
      return const Right(unit);
    }
    if (leida case Left(value: FailureAlmacenSeguro()) || Right(value: null)) {
      return Left(_sinDek(estado));
    }
    return Left((leida as Left<Failure, ClaveDb?>).value);
  }

  Future<Either<Failure, ResultadoInicializacionDb>> _abrirExistente(
    InicializarDbLocalParams params,
    TestigoSesion testigo,
    EstadoDbLocal estado,
  ) async {
    final leida = await _repository.leerDek();
    if (leida case Left(value: FailureAlmacenSeguro()) || Right(value: null)) {
      return Left(_sinDek(estado));
    }
    if (leida case Left(value: final falla)) return Left(falla);
    final dek = leida._valor!;

    final password = params.password;
    if (password == null && params.requiereEnvoltorio && !estado.envoltorioExiste) {
      // Abriría sin envoltorio una cuenta que tiene contraseña: primero, la contraseña.
      dek.destruir();
      return const Left(FailurePasswordParaProteger());
    }
    if (password != null && !estado.envoltorioExiste) {
      // Login con contraseña en un equipo sin envoltorio: se arma ahora, así hay con qué recuperar
      // si el Keystore falla. Si no se puede, igual se abre: la DB está bien y el envoltorio se
      // vuelve a intentar en el próximo login (la falla ya quedó en el log).
      params.alAvanzar?.call(PasoInicializacionDb.protegiendoClave);
      await _repository.envolverConPassword(dek, password);
    }

    params.alAvanzar?.call(PasoInicializacionDb.abriendoDb);
    final abierta = await _repository.abrirSiSigueVigente(dek, testigo);
    return abierta.map((_) => ResultadoInicializacionDb.abierta);
  }

  Future<Either<Failure, ResultadoInicializacionDb>> _crearDesdeCero(
    InicializarDbLocalParams params,
    TestigoSesion testigo,
  ) async {
    // Una DB nueva de una cuenta con contraseña nace con envoltorio: sin la contraseña, no se toca
    // nada y se pide.
    if (params.password == null && params.requiereEnvoltorio) {
      return const Left(FailurePasswordParaProteger());
    }

    // Las dos verificaciones van antes de tocar nada: si no se sigue, el dispositivo queda como
    // estaba.
    final bloqueo = await _repository.tieneBloqueoPantalla();
    if (bloqueo case Left(value: final falla)) return Left(falla);
    if (bloqueo case Right(value: false)) return const Left(FailureSinBloqueoPantalla());

    final nivel = await _repository.nivelAlmacenSeguro();
    if (nivel case Left(value: final falla)) return Left(falla);
    final porSoftware = nivel._valor == NivelAlmacenSeguro.software;
    if (porSoftware && !params.aceptaAlmacenSoftware) return const Left(FailureAlmacenPocoSeguro());

    // Si no se pudo limpiar no se sigue: una DEK nueva contra un archivo viejo no lo abriría.
    final limpio = await _repository.descartar();
    if (limpio case Left(value: final falla)) return Left(falla);

    if (porSoftware) {
      final registrado = await _repository.registrarConsentimientoAlmacenSoftware();
      if (registrado case Left(value: final falla)) return _abortar(falla);
    }

    params.alAvanzar?.call(PasoInicializacionDb.generandoClave);
    final creada = await _repository.crearDek();
    if (creada case Left(value: final falla)) return _abortar(falla);
    final dek = creada._valor;

    final password = params.password;
    if (password != null) {
      params.alAvanzar?.call(PasoInicializacionDb.protegiendoClave);
      final envuelta = await _repository.envolverConPassword(dek, password);
      if (envuelta case Left(value: final falla)) {
        dek.destruir();
        return _abortar(falla);
      }
    }

    params.alAvanzar?.call(PasoInicializacionDb.abriendoDb);
    final abierta = await _repository.abrirSiSigueVigente(dek, testigo);
    if (abierta case Left(value: final falla)) return _abortar(falla);

    final marcada = await _repository.marcarInicializada();
    if (marcada case Left(value: final falla)) return _abortar(falla);

    return const Right(ResultadoInicializacionDb.creada);
  }

  /// El almacén no tiene la DEK (o no responde) con la DB en disco: recuperación guiada de
  /// ADR-006. Nada se borra acá.
  static Failure _sinDek(EstadoDbLocal estado) => estado.envoltorioExiste
      ? const FailureAlmacenSeguroRecuperable()
      : const FailureAlmacenSeguroSinRecuperacion();

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

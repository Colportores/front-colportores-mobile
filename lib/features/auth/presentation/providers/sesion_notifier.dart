import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/entities/resultado_cierre_sesion.dart';
import '../../domain/entities/resultado_registro.dart';
import '../../domain/entities/resumen_datos_locales.dart';
import '../../domain/entities/sesion.dart';
import '../../domain/usecases/borrar_datos_locales_use_case.dart';
import '../../domain/usecases/iniciar_sesion_use_case.dart';
import '../../domain/usecases/reenviar_verificacion_use_case.dart';
import '../../domain/usecases/registrar_usuario_use_case.dart';
import 'auth_providers.dart';

part 'sesion_notifier.g.dart';

/// Estado de sesión de la app. `null` = nadie logueado.
///
/// La UI observa `sesionProvider` (el generador quita el sufijo `Notifier`); los formularios
/// llaman a [iniciarSesion] y [cerrarSesion]. Sin lógica de negocio acá (vive en los use cases):
/// solo traducción a estado.
@Riverpod(keepAlive: true)
class SesionNotifier extends _$SesionNotifier {
  /// El generador lo construye sin argumentos; [logger] existe para que los tests lo inyecten,
  /// como en el resto del proyecto.
  SesionNotifier({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<Sesion?> build() async {
    final resultado = await ref.watch(obtenerSesionActualUseCaseProvider)(const NoParams());
    _reintentarRevocacionPendiente();
    return resultado.fold((_) => null, (sesion) => sesion);
  }

  /// Devuelve el [Failure] si falló (para que el formulario lo muestre) o `null` si entró.
  Future<Failure?> iniciarSesion({required String email, required String password}) async {
    state = const AsyncLoading();
    final resultado = await ref.read(iniciarSesionUseCaseProvider)(
      IniciarSesionParams(email: email, password: password),
    );

    return resultado.fold(
      (failure) {
        state = const AsyncData(null);
        return failure;
      },
      (sesion) {
        state = AsyncData(sesion);
        // Entrar prueba que hay red: momento de revocar lo que un logout sin red dejó pendiente.
        _reintentarRevocacionPendiente();
        return null;
      },
    );
  }

  /// Ingreso con Google (HU-AUTH-003): abre el navegador y espera el deep link de vuelta.
  /// Mismo contrato que [iniciarSesion]: el [Failure] si falló o `null` si entró.
  Future<Failure?> iniciarSesionConGoogle() async {
    state = const AsyncLoading();
    final resultado = await ref.read(iniciarSesionConGoogleUseCaseProvider)(const NoParams());

    return resultado.fold(
      (failure) {
        state = const AsyncData(null);
        return failure;
      },
      (sesion) {
        state = AsyncData(sesion);
        return null;
      },
    );
  }

  /// Registra una cuenta nueva (HU-AUTH-001/002, ver dartdoc de [RegistrarUsuarioUseCase]).
  ///
  /// A diferencia de [iniciarSesion], devuelve el `Either` completo en vez de solo el [Failure]:
  /// la página necesita distinguir error / éxito con sesión / éxito con verificación pendiente
  /// (sesión `null`), no solo si falló.
  Future<Either<Failure, ResultadoRegistro>> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
    required bool aceptaTerminos,
  }) async {
    state = const AsyncLoading();
    final resultado = await ref.read(registrarUsuarioUseCaseProvider)(
      RegistrarUsuarioParams(
        nombre: nombre,
        apellido: apellido,
        cedula: cedula,
        email: email,
        password: password,
        aceptaTerminos: aceptaTerminos,
      ),
    );

    return resultado.fold(
      (failure) {
        state = const AsyncData(null);
        return Left(failure);
      },
      (r) {
        state = AsyncData(r.sesion);
        return Right(r);
      },
    );
  }

  /// Reenvía el email de verificación (HU-AUTH-002). No toca el estado de sesión: la cuenta sigue
  /// sin poder entrar hasta que el usuario confirme el correo, se reenvíe o no.
  Future<Failure?> reenviarVerificacion(String email) async {
    final resultado = await ref.read(reenviarVerificacionUseCaseProvider)(
      ReenviarVerificacionParams(email: email),
    );
    return resultado.fold((failure) => failure, (_) => null);
  }

  /// Cierra la sesión (HU-AUTH-006): revoca el JWT —o lo deja pendiente sin red—, borra la sesión
  /// guardada, cierra la DB y destruye la DEK en claro. Los datos del teléfono se conservan: el
  /// próximo login reabre todo. Borrarlos es [borrarDatosLocales] (HU-AUTH-010).
  ///
  /// Es todo o nada desde el punto de vista del usuario (#54):
  /// - `Left`: la sesión guardada no se pudo borrar. **No** se toca nada más: el usuario sigue
  ///   adentro, con la DB abierta, y la pantalla le ofrece reintentar. Resetear el estado acá haría
  ///   creer que salió cuando la sesión sigue en el teléfono.
  /// - `Right`: se cierra la DB y el estado pasa a `null` (la app vuelve al login). Si cerrar la
  ///   DB falla, ya lo loguea `DatabaseHelper` como `CLOSE_FAIL` y el usuario no puede hacer nada:
  ///   no se le muestra, y el estado se resetea igual.
  ///
  /// Si el use case **lanza** (no debería: el repositorio traduce todo a `Failure`), la DB se cierra
  /// igual, el estado se resetea y la excepción se propaga: deslogueado en pantalla con la DB
  /// abierta y la clave viva sería peor.
  Future<Either<Failure, ResultadoCierreSesion>> cerrarSesion() async {
    final Either<Failure, ResultadoCierreSesion> resultado;
    try {
      resultado = await ref.read(cerrarSesionUseCaseProvider)(const NoParams());
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'LOGOUT_FAIL',
        'el cierre de sesión falló; se cierra igual la DB local',
        const {},
        e,
        st,
      );
      await _cerrarDbYSesion();
      rethrow;
    }

    if (resultado.isRight()) await _cerrarDbYSesion();
    return resultado;
  }

  /// Borra los datos del teléfono y cierra la sesión (HU-AUTH-010). Si el borrado se niega (hay
  /// operaciones sin sincronizar) o falla, la sesión sigue abierta y el `Left` dice por qué.
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrarDatosLocales({
    required bool incluirBackupDrive,
  }) async {
    final resultado = await ref.read(borrarDatosLocalesUseCaseProvider)(
      BorrarDatosLocalesParams(incluirBackupDrive: incluirBackupDrive),
    );
    if (resultado.isRight()) state = const AsyncData(null);
    return resultado;
  }

  Future<void> _cerrarDbYSesion() async {
    try {
      await ref.read(dbLocalProvider.notifier).cerrar();
    } on Object {
      // Ya logueado por `DatabaseHelper` (`CLOSE_FAIL`); la clave se destruye igual.
    } finally {
      state = const AsyncData(null);
    }
  }

  /// Best-effort: un logout sin red dejó la revocación del JWT pendiente (HU-AUTH-006). Sin red
  /// sigue pendiente y no se avisa — el usuario no puede hacer nada con eso.
  void _reintentarRevocacionPendiente() =>
      unawaited(ref.read(reintentarRevocacionPendienteUseCaseProvider)(const NoParams()));
}

import 'package:dartz/dartz.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/entities/resultado_registro.dart';
import '../../domain/entities/sesion.dart';
import '../../domain/usecases/iniciar_sesion_use_case.dart';
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

  /// Invalida la sesión y cierra la DB local: la clave de cifrado se destruye acá (HU-AUTH-006,
  /// ADR-003 — vive solo mientras la sesión está activa). El borrado de datos es HU-AUTH-010.
  ///
  /// Los tres pasos no dependen uno del otro:
  /// - La DB local se cierra **aunque el use case lance** (por ejemplo, si el almacén seguro falla
  ///   al leer la sesión). Si no, el estado diría "deslogueado" con la DB abierta y la clave viva.
  /// - El estado se resetea aunque falle el cierre de la DB: la sesión remota ya puede estar
  ///   invalidada, y dejar la app mostrando al usuario como logueado sería peor que el error.
  ///
  /// La excepción igual se propaga para quien sí espere el `Future`. Si fallan los dos pasos, se
  /// propaga **la del use case**: es la que dice que el logout no se completó (el JWT puede no
  /// haberse revocado y la sesión local seguir guardada), y es la única que no deja rastro en otro
  /// lado — la del cierre de la DB ya la loguea `DatabaseHelper` como `CLOSE_FAIL`.
  Future<void> cerrarSesion() async {
    Object? fallaLogout;
    StackTrace? rastroLogout;
    try {
      await ref.read(cerrarSesionUseCaseProvider)(const NoParams());
    } on Object catch (e, st) {
      fallaLogout = e;
      rastroLogout = st;
      _log.error(
        LogModulo.auth,
        'LOGOUT_FAIL',
        'el cierre de sesión falló; se cierra igual la DB local',
        const {},
        e,
        st,
      );
    }

    try {
      await ref.read(dbLocalProvider.notifier).cerrar();
    } on Object {
      // Con el logout ya fallado, la causa que se propaga es esa (ver arriba).
      if (fallaLogout == null) rethrow;
    } finally {
      state = const AsyncData(null);
    }

    if (fallaLogout != null) Error.throwWithStackTrace(fallaLogout, rastroLogout!);
  }
}

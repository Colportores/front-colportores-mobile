import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
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

  /// Registra una cuenta nueva y, si sale bien, deja la sesión iniciada (HU-AUTH-001, versión
  /// mockeada — ver dartdoc de [RegistrarUsuarioUseCase] sobre qué puede cambiar con Supabase
  /// Auth real). Devuelve el [Failure] si falló o `null` si se registró.
  Future<Failure?> registrar({
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
        return failure;
      },
      (sesion) {
        state = AsyncData(sesion);
        return null;
      },
    );
  }

  /// Invalida la sesión y cierra la DB local: la clave de cifrado se destruye acá (HU-AUTH-006,
  /// ADR-003 — vive solo mientras la sesión está activa). El borrado de datos es HU-AUTH-010.
  Future<void> cerrarSesion() async {
    await ref.read(cerrarSesionUseCaseProvider)(const NoParams());
    await ref.read(dbLocalProvider.notifier).cerrar();
    state = const AsyncData(null);
  }
}

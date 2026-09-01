import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/entities/sesion.dart';
import '../../domain/usecases/iniciar_sesion_use_case.dart';
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

  Future<void> cerrarSesion() async {
    await ref.read(cerrarSesionUseCaseProvider)(const NoParams());
    state = const AsyncData(null);
  }
}

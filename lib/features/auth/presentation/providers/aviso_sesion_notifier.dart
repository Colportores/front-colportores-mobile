import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/error/failure.dart';

part 'aviso_sesion_notifier.g.dart';

/// Por qué la app volvió al login sin que el usuario cerrara sesión (HU-AUTH-007): la sesión
/// venció por inactividad ([FailureSesionExpiradaPorInactividad]) o el servidor la revocó
/// ([FailureSesionRevocada]). El login lo muestra hasta que el usuario vuelve a entrar.
@Riverpod(keepAlive: true)
class AvisoSesion extends _$AvisoSesion {
  @override
  Failure? build() => null;

  void mostrar(Failure aviso) => state = aviso;

  void descartar() => state = null;
}

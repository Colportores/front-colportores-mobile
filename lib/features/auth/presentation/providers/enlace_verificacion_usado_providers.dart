import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/destino_enlace_verificacion_usado.dart';
import '../../domain/usecases/decidir_destino_enlace_verificacion_usado_use_case.dart';
import 'sesion_notifier.dart';

/// El email y la contraseña con los que la pantalla de espera de verificación está abierta, solo
/// en memoria mientras esa pantalla vive (HU-AUTH-002: login en silencio «sin persistir la
/// contraseña»).
final class DatosDeEsperaVerificacion extends Equatable {
  const DatosDeEsperaVerificacion({required this.email, required this.password});

  final String email;
  final String password;

  /// Sin esto, cualquier interpolación (un log, una excepción) filtraría la contraseña
  /// (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [email, password];
}

/// Los datos de la pantalla de espera abierta (`null` si no hay una con email y contraseña).
final verificacionEnEsperaProvider =
    NotifierProvider<VerificacionEnEsperaNotifier, DatosDeEsperaVerificacion?>(
      VerificacionEnEsperaNotifier.new,
    );

class VerificacionEnEsperaNotifier extends Notifier<DatosDeEsperaVerificacion?> {
  @override
  DatosDeEsperaVerificacion? build() => null;

  void abrir(DatosDeEsperaVerificacion datos) {
    if (ref.mounted) state = datos;
  }

  /// Cierra [datos] solo si siguen siendo los vigentes: otra pantalla de espera pudo abrirse antes
  /// de que esta termine de cerrarse.
  void cerrar(DatosDeEsperaVerificacion datos) {
    if (ref.mounted && identical(state, datos)) state = null;
  }
}

/// Resultado de resolver un enlace de verificación con `otp_expired`.
final class EnlaceVerificacionResuelto {
  const EnlaceVerificacionResuelto({required this.destino, this.email = ''});

  final DestinoEnlaceVerificacionUsado destino;

  /// El email de la pantalla de espera que estaba abierta (vacío si no había ninguna).
  final String email;
}

final decidirDestinoEnlaceVerificacionUsadoUseCaseProvider =
    Provider<DecidirDestinoEnlaceVerificacionUsadoUseCase>(
      (ref) => const DecidirDestinoEnlaceVerificacionUsadoUseCase(),
    );

/// Resuelve qué mostrar cuando llega un enlace de verificación con `otp_expired`
/// (HU-AUTH-002). Un solo enlace se resuelve a la vez: mientras el login en silencio está en
/// curso, otro evento igual se descarta (dos aperturas del mismo enlace no hacen dos logins).
final resolutorEnlaceVerificacionUsadoProvider =
    NotifierProvider<ResolutorEnlaceVerificacionUsado, bool>(ResolutorEnlaceVerificacionUsado.new);

class ResolutorEnlaceVerificacionUsado extends Notifier<bool> {
  /// El estado es «hay una resolución en curso».
  @override
  bool build() => false;

  /// `null` si ya había una resolución en curso. Nunca lanza.
  Future<EnlaceVerificacionResuelto?> resolver() async {
    if (state) return null;
    state = true;
    try {
      final haySesion = await _haySesion();
      final espera = ref.read(verificacionEnEsperaProvider);
      final resultado = await ref.read(decidirDestinoEnlaceVerificacionUsadoUseCaseProvider)(
        DecidirDestinoEnlaceParams(
          haySesion: haySesion,
          loginEnSilencio: espera == null
              ? null
              : () => ref
                    .read(sesionProvider.notifier)
                    .iniciarSesion(email: espera.email, password: espera.password),
        ),
      );
      final destino = resultado.getOrElse(() => DestinoEnlaceVerificacionUsado.noSabemos);
      return EnlaceVerificacionResuelto(destino: destino, email: espera?.email ?? '');
    } finally {
      if (ref.mounted) state = false;
    }
  }

  /// Espera a que la sesión termine de resolverse (arranque en frío): ver `app.dart`.
  Future<bool> _haySesion() async {
    try {
      return await ref.read(sesionProvider.future) != null;
    } on Object {
      return false;
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/aviso_privacidad_repository_impl.dart';
import '../../domain/repositories/aviso_privacidad_repository.dart';

/// Dónde se guarda qué cuentas escondieron el aviso de privacidad. En el equipo `main.dart` lo
/// sobreescribe con el almacén seguro; por defecto (tests), en memoria.
final avisoPrivacidadRepositoryProvider = Provider<AvisoPrivacidadRepository>(
  (ref) => AvisoPrivacidadEnMemoria(),
);

/// Si la cuenta [cuentaId] escondió el aviso «Estos datos solo viven en tu celular. Nunca se suben a
/// la nube.» (`true` = escondido). Una sola preferencia para los dos lugares donde sale el aviso: el
/// alta de persona (HU-UBI-008) y las notas (HU-UBI-012), y el interruptor de Configuración
/// («Mostrar el aviso de privacidad»).
///
/// Mientras se lee, o si no se pudo leer, el estado es «no escondido»: ante la duda el aviso se ve.
final avisoPrivacidadOcultoProvider =
    AsyncNotifierProvider.family<AvisoPrivacidadOcultoNotifier, bool, String>(
      AvisoPrivacidadOcultoNotifier.new,
    );

class AvisoPrivacidadOcultoNotifier extends AsyncNotifier<bool> {
  AvisoPrivacidadOcultoNotifier(this.cuentaId);

  /// UUID del usuario con la sesión iniciada.
  final String cuentaId;

  /// Hay un cambio en curso. Es un campo y no solo el estado: la guarda tiene que cortar el segundo
  /// toque aunque llegue antes de que el cambio termine.
  bool _enCurso = false;

  @override
  Future<bool> build() => ref.watch(avisoPrivacidadRepositoryProvider).estaOculto(cuentaId);

  /// Esconde el aviso. Devuelve `true` si quedó guardado; con `false` el aviso sigue a la vista (no
  /// se pudo guardar, o ya había un cambio en curso).
  Future<bool> ocultar() => _cambiar(oculto: true);

  /// Vuelve a mostrar el aviso. Devuelve `true` si quedó guardado.
  Future<bool> mostrar() => _cambiar(oculto: false);

  Future<bool> _cambiar({required bool oculto}) async {
    if (_enCurso) return false;
    _enCurso = true;
    try {
      final repo = ref.read(avisoPrivacidadRepositoryProvider);
      if (oculto) {
        await repo.ocultar(cuentaId);
      } else {
        await repo.mostrar(cuentaId);
      }
      if (ref.mounted) state = AsyncData(oculto);
      return true;
    } on Object {
      return false;
    } finally {
      _enCurso = false;
    }
  }
}

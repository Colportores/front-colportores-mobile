import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/sincronizacion/data/repositories/modo_ahorro_repository_impl.dart';
import '../../features/sincronizacion/domain/repositories/modo_ahorro_repository.dart';
import '../database/database_providers.dart';
import '../logging/app_logger.dart';

/// Lo que el teléfono recuerda del modo ahorro de datos (HU-SYNC-008). En el equipo, `main.dart` lo
/// sobreescribe con el almacén seguro; por defecto (tests), en memoria.
final modoAhorroRepositoryProvider = Provider<ModoAhorroRepository>(
  (ref) => ModoAhorroRepositoryEnMemoria(),
);

/// El modo ahorro guardado al abrir la app. Leerlo del almacén seguro es asincrónico y el motor lo
/// necesita al armarse (el primer ciclo ya puede bajar por datos móviles), así que `main.dart` lo
/// carga antes de `runApp` y lo sobreescribe. Por defecto, apagado: el comportamiento estándar.
final modoAhorroInicialProvider = Provider<bool>((ref) => false);

/// Si el modo ahorro de datos está activo ahora (HU-SYNC-008). Es la fuente de la pantalla de
/// sincronización y de lo que se le dice al motor: el motor lo recibe al armarse
/// (`motorSyncProvider`) y en cada cambio.
final modoAhorroProvider = NotifierProvider<ModoAhorroNotifier, bool>(ModoAhorroNotifier.new);

class ModoAhorroNotifier extends Notifier<bool> {
  /// Los cambios se hacen de a uno, en el orden en que se piden: dos toques seguidos no se pisan.
  Future<void> _cola = Future<void>.value();

  /// El valor de ahora, para devolverlo mientras se vuelve a leer lo guardado.
  bool _valor = false;
  bool _primera = true;

  @override
  bool build() {
    // La DB se abre en cada ingreso: lo guardado se vuelve a leer, por si el borrado de datos
    // locales (HU-AUTH-010) lo apagó entre una sesión y la siguiente.
    ref.watch(dbLocalProvider);
    if (_primera) {
      _primera = false;
      _valor = ref.read(modoAhorroInicialProvider);
    } else {
      unawaited(_releer());
    }
    return _valor;
  }

  Future<void> _releer() async {
    final guardado = await ref.read(modoAhorroRepositoryProvider).leer();
    if (ref.mounted && guardado != _valor) state = _valor = guardado;
  }

  /// Activa o apaga el modo. Lo aplica ya (el motor y la pantalla) y lo guarda; si no se pudo
  /// guardar vuelve al valor anterior y devuelve `false`, para que la pantalla lo diga: un modo que
  /// parece activo y al reiniciar la app vuelve a estar apagado gastaría datos sin avisar.
  Future<bool> cambiar({required bool activo}) {
    final resultado = _cola.then((_) => _aplicar(activo));
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  Future<bool> _aplicar(bool activo) async {
    final anterior = state;
    if (anterior == activo) return true;
    state = _valor = activo;
    final repositorio = ref.read(modoAhorroRepositoryProvider);
    try {
      await repositorio.guardar(activo: activo);
      return true;
    } on Object catch (e, st) {
      AppLogger.instance.error(
        LogModulo.sync,
        'MODO_AHORRO_GUARDAR',
        'no se pudo guardar el modo ahorro de datos',
        {'activo': activo},
        e,
        st,
      );
      state = _valor = anterior;
      return false;
    }
  }
}

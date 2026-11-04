import '../logging/app_logger.dart';

/// Saca de `sync_queue` los envíos ya confirmados (`DONE`) de hace más de 7 días (#188).
///
/// El motor sabe hacerlo (`SyncEngine.purge`) pero nadie lo llamaba: sin esto la cola de un teléfono
/// que lleva meses en la calle crece con cada venta que ya está en el servidor. Un `DONE` reciente
/// se conserva porque de él sale la fecha del último envío; los que esperan, fallaron o están en
/// conflicto no se tocan (la purga solo mira `DONE`).
///
/// Es de segundo plano: **nunca lanza** y no admite dos corridas a la vez (un ciclo que termina
/// mientras otra purga sigue en curso no encola una segunda). Quien la dispara no la espera: ni el
/// arranque ni el sync dependen de ella.
final class PurgaDeLaCola {
  PurgaDeLaCola(this._purgar);

  /// Lo que borra y devuelve cuántos `DONE` sacó; en la app, `SyncEngine.purge`.
  final Future<int> Function() _purgar;

  var _corriendo = false;

  /// `true` mientras hay una purga en curso.
  bool get corriendo => _corriendo;

  /// Corre una purga, o no hace nada si ya hay una. Un fallo (la base cerrada al cerrar sesión, un
  /// error de disco) se registra y no se propaga: el próximo ciclo la vuelve a intentar.
  Future<void> correr() async {
    if (_corriendo) return;
    _corriendo = true;
    try {
      final borrados = await _purgar();
      if (borrados > 0) {
        AppLogger.instance.info(
          LogModulo.sync,
          'COLA_PURGADA',
          'se sacaron de la cola los envíos confirmados de hace más de 7 días',
          {'cantidad': borrados},
        );
      }
    } on Object catch (e, st) {
      AppLogger.instance.error(
        LogModulo.sync,
        'COLA_PURGA_FAIL',
        'falló la purga de la cola; se reintenta en el próximo ciclo',
        const {},
        e,
        st,
      );
    } finally {
      _corriendo = false;
    }
  }
}

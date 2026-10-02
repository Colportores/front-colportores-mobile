/// Reloj que no se deja mover desde los ajustes del teléfono mientras la app está abierta.
///
/// Toma la hora del equipo **una sola vez**, al crearse, y desde ahí avanza con un cronómetro
/// monótono: adelantar o atrasar el reloj del sistema no cambia lo que devuelve [ahora]. Sirve para
/// medir esperas de seguridad (el bloqueo del borrado de datos, HU-AUTH-010): adelantar la hora no
/// las destraba.
///
/// Límites, a propósito: el cronómetro no cuenta el tiempo con el equipo dormido (la espera puede
/// durar un poco más: falla cerrado) y un instante guardado antes de cerrar la app se compara contra
/// la hora del sistema de la corrida siguiente, que sí puede haberse movido entre una y otra.
final class RelojMonotono {
  RelojMonotono({DateTime Function()? sistema, Duration Function()? transcurrido})
    : _base = (sistema ?? DateTime.now)().toUtc(),
      _transcurrido = transcurrido ?? _cronometroNuevo();

  final DateTime _base;
  final Duration Function() _transcurrido;

  static Duration Function() _cronometroNuevo() {
    final cronometro = Stopwatch()..start();
    return () => cronometro.elapsed;
  }

  /// La hora de ahora, en UTC: la del arranque más lo que corrió el cronómetro.
  DateTime ahora() => _base.add(_transcurrido());
}

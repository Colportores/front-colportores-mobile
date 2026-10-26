/// Cómo se dicen las fechas de la vista 25: «recién», «hace 3 min», «hace 2 h», «hoy 03:10»,
/// «ayer 21:00». Todo en la hora local del teléfono. Una fecha del futuro (el reloj del teléfono se
/// atrasó) se dice «recién»: no se inventa una espera.
abstract final class FormatoSincronizacion {
  static String _dos(int n) => n.toString().padLeft(2, '0');

  static String _hora(DateTime f) => '${_dos(f.hour)}:${_dos(f.minute)}';

  /// «22/10».
  static String dia(DateTime fecha) {
    final f = fecha.toLocal();
    return '${_dos(f.day)}/${_dos(f.month)}';
  }

  /// «22/10 14:20».
  static String diaYHora(DateTime fecha) {
    final f = fecha.toLocal();
    return '${dia(f)} ${_hora(f)}';
  }

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _segunElDia(DateTime f, DateTime ahora) {
    if (_mismoDia(f, ahora)) return 'hoy ${_hora(f)}';
    final ayer = DateTime(ahora.year, ahora.month, ahora.day - 1);
    if (_mismoDia(f, ayer)) return 'ayer ${_hora(f)}';
    return diaYHora(f);
  }

  /// Para el último envío y la última actualización: «recién», «hace N min», «hace N h» el mismo
  /// día, y después «ayer 21:00» o «22/10 14:20».
  static String hace(DateTime fecha, DateTime ahora) {
    final f = fecha.toLocal();
    final a = ahora.toLocal();
    final pasado = a.difference(f);
    if (pasado < const Duration(minutes: 1)) return 'recién';
    if (pasado < const Duration(hours: 1)) return 'hace ${pasado.inMinutes} min';
    if (_mismoDia(f, a)) return 'hace ${pasado.inHours} h';
    return _segunElDia(f, a);
  }

  /// Para el último respaldo: «recién», «hoy 03:10», «ayer 03:10» o «22/10 03:10».
  static String reloj(DateTime fecha, DateTime ahora) {
    final f = fecha.toLocal();
    final a = ahora.toLocal();
    if (a.difference(f) < const Duration(minutes: 1)) return 'recién';
    return _segunElDia(f, a);
  }
}

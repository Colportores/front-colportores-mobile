/// Cómo se escriben el día y la hora en «Agendar una visita» (vista 23 A). Siempre en la hora del
/// teléfono, sin `intl`: es-UY, `DD/MM`, 24 horas.
abstract final class FormatoAgendarVisita {
  static const _diasLargos = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  static const _diasCortos = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  /// «14:30».
  static String hora(DateTime t) => minutosComoHora(t.hour * 60 + t.minute);

  /// «14:30» para [minutos] desde la medianoche.
  static String minutosComoHora(int minutos) =>
      '${(minutos ~/ 60).toString().padLeft(2, '0')}:${(minutos % 60).toString().padLeft(2, '0')}';

  /// «24/10».
  static String diaYMes(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

  /// «Jueves 24/10».
  static String diaLargo(DateTime t) => '${_diasLargos[t.weekday - 1]} ${diaYMes(t)}';

  /// «Jue 24/10»: el día en el detalle de la agenda (23C·01).
  static String diaCortoYMes(DateTime t) => '${_diasCortos[t.weekday - 1]} ${diaYMes(t)}';

  /// «Jue 24»: el chip de un día de la semana que viene.
  static String diaCorto(DateTime t) => '${_diasCortos[t.weekday - 1]} ${t.day}';

  /// Si [a] y [b] son el mismo día del calendario (hora local).
  static bool mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// El día [t] a medianoche, sin horas.
  static DateTime soloDia(DateTime t) => DateTime(t.year, t.month, t.day);

  /// El campo «DÍA Y HORA»: «Hoy · 11:00», «Mañana · 09:00», «Jueves 24/10 · 14:30».
  static String cuando(DateTime fecha, DateTime ahora) {
    final dia = soloDia(fecha);
    final hoy = soloDia(ahora);
    final nombre = mismoDia(dia, hoy)
        ? 'Hoy'
        : mismoDia(dia, DateTime(hoy.year, hoy.month, hoy.day + 1))
        ? 'Mañana'
        : diaLargo(dia);
    return '$nombre · ${hora(fecha)}';
  }

  /// La frase de «Esa hora ya pasó»: «Hoy a las 11:00» o «El lun 12/10 a las 11:00».
  static String cuandoEnFrase(DateTime fecha, DateTime ahora) {
    if (mismoDia(fecha, ahora)) return 'Hoy a las ${hora(fecha)}';
    return 'El ${_diasCortos[fecha.weekday - 1].toLowerCase()} ${diaYMes(fecha)} a las ${hora(fecha)}';
  }

  /// Las iniciales de una persona («MF»): la primera letra del nombre y del apellido; con uno solo,
  /// la primera de ese. Vacío si no hay ninguno.
  static String iniciales(String nombre, String apellido) {
    String primera(String s) {
      final limpio = s.trim();
      return limpio.isEmpty ? '' : String.fromCharCodes(limpio.runes.take(1)).toUpperCase();
    }

    return '${primera(nombre)}${primera(apellido)}';
  }
}

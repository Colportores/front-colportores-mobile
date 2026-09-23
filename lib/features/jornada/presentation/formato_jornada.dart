/// Formatos de fecha y hora de la pantalla de jornada, en la zona del dispositivo.
///
/// A mano y en español rioplatense: la app todavía no tiene `intl` ni localizaciones (cuando
/// entren, esto pasa a `DateFormat`).
library;

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String _dosDigitos(int n) => n.toString().padLeft(2, '0');

/// `14:05`.
String horaCorta(DateTime instante) {
  final local = instante.toLocal();
  return '${_dosDigitos(local.hour)}:${_dosDigitos(local.minute)}';
}

/// `martes 23 de septiembre`.
String fechaLarga(DateTime instante) {
  final local = instante.toLocal();
  return '${_dias[local.weekday - 1]} ${local.day} de ${_meses[local.month - 1]}';
}

/// `menos de 1 min`, `12 min`, `2 h`, `1 h 20 min`.
String duracionCorta(Duration duracion) {
  final minutos = duracion.inMinutes;
  if (minutos < 1) return 'menos de 1 min';
  final horas = minutos ~/ 60;
  final resto = minutos % 60;
  if (horas == 0) return '$resto min';
  if (resto == 0) return '$horas h';
  return '$horas h $resto min';
}

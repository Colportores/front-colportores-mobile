import '../../jornada/presentation/formato_jornada.dart';
import 'widgets/textos_centro_notificaciones.dart';

const _meses = [
  'ENERO',
  'FEBRERO',
  'MARZO',
  'ABRIL',
  'MAYO',
  'JUNIO',
  'JULIO',
  'AGOSTO',
  'SEPTIEMBRE',
  'OCTUBRE',
  'NOVIEMBRE',
  'DICIEMBRE',
];

/// El día de un aviso como rótulo de la lista (24C·01): `HOY`, `AYER`, `LUNES 21` dentro de la
/// semana y `21 DE SEPTIEMBRE` más atrás. Los días se cuentan en la zona del dispositivo, a
/// medianoche: un aviso de las 23:50 de ayer es de ayer aunque hayan pasado diez minutos.
String rotuloDelDia(DateTime recibida, {required DateTime ahora}) {
  final dia = recibida.toLocal();
  final hoy = ahora.toLocal();
  final dias = DateTime.utc(
    hoy.year,
    hoy.month,
    hoy.day,
  ).difference(DateTime.utc(dia.year, dia.month, dia.day)).inDays;
  if (dias <= 0) return TextosCentroNotificaciones.hoy;
  if (dias == 1) return TextosCentroNotificaciones.ayer;
  if (dias < 7) return diaCorto(dia).toUpperCase();
  return '${dia.day} DE ${_meses[dia.month - 1]}';
}

/// La hora de un aviso: `15:30`.
String horaDelAviso(DateTime recibida) => horaCorta(recibida);

import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

tz.Location? _montevideo;

tz.Location _zona() {
  final cargada = _montevideo;
  if (cargada != null) return cargada;
  tz_data.initializeTimeZones();
  return _montevideo = tz.getLocation('America/Montevideo');
}

/// El día de calendario de [momento] en Montevideo (`America/Montevideo`), como `AAAA-MM-DD`.
///
/// Es «hoy» para todo el sistema (docs 08 §8.6; en el servidor, `hoy_montevideo()` de la migración
/// 0024): no depende de la zona horaria del teléfono ni de la de quien pregunta. Las fechas de las
/// réplicas que son un `date` en el cloud (el fin de una campaña, la vigencia de un precio) se guardan
/// como ese texto y se comparan con él: un día de calendario no es un instante, y pasarlo por UTC lo
/// correría un día cerca de la medianoche.
String diaDeCalendario(DateTime momento) {
  final t = tz.TZDateTime.from(momento.toUtc(), _zona());
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${dos(t.month)}-${dos(t.day)}';
}

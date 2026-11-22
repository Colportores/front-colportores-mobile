/// La hora local en que arranca la ventana nocturna del respaldo (HU-SYNC-005: «nocturno», 03:00).
const horaDeLaVentanaNocturna = 3;

/// Cuánto falta para la próxima ventana nocturna: las [hora] de la noche en hora local, la de hoy si
/// todavía no llegó y la de mañana si ya pasó (a las 03:00 en punto, la de mañana).
///
/// Se arma con el calendario local y no sumando 24 horas, para que un cambio de hora no la corra.
/// Con el valor de acá se programa la tarea periódica: el sistema la repite cada 24 horas a partir de
/// ese momento.
Duration esperaHastaLaVentanaNocturna(DateTime ahora, {int hora = horaDeLaVentanaNocturna}) {
  final local = ahora.toLocal();
  var proxima = DateTime(local.year, local.month, local.day, hora);
  if (!proxima.isAfter(local)) {
    proxima = DateTime(local.year, local.month, local.day + 1, hora);
  }
  return proxima.difference(local);
}

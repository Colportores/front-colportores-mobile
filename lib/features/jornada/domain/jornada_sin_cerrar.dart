/// Las reglas de HU-JOR-002 «Jornada que quedó abierta» en Dart puro. Las comparten el caso de uso
/// (`FinalizarJornadaUseCase`) y la pantalla «¿A qué hora terminaste?», para que ofrezcan y
/// validen exactamente lo mismo.
abstract final class JornadaSinCerrar {
  /// Hasta cuánto después del inicio puede caer el fin de una jornada que quedó abierta, aunque
  /// cruce la medianoche (decisión de Cristian, 30/09, en #230; HU-JOR-002): así una jornada
  /// iniciada a las 23:59 tiene salida y nunca se inventa un fin.
  static const maximoDespuesDelInicio = Duration(hours: 12);

  /// Si la jornada que empezó en [inicio] quedó abierta de un día anterior: ni la hora más
  /// temprana del margen normal de [ahora] ([margen] hacia atrás, y nunca antes del inicio) cae en
  /// el día del inicio, en la zona del dispositivo. Cerrarla con la hora de hoy inventaría un fin;
  /// hay que preguntar a qué hora terminó.
  static bool quedoAbierta({
    required DateTime inicio,
    required DateTime ahora,
    required Duration margen,
  }) {
    final haceMargen = _alMinuto(ahora.subtract(margen));
    final desde = inicio.isAfter(haceMargen) ? inicio : haceMargen;
    return caeEnOtroDia(inicio, desde);
  }

  /// Si [instante] cae en un día calendario posterior al de [inicio], en la zona del dispositivo
  /// (el día del colportor, no el de UTC).
  static bool caeEnOtroDia(DateTime inicio, DateTime instante) {
    final i = inicio.toLocal();
    final x = instante.toLocal();
    return DateTime(i.year, i.month, i.day).isBefore(DateTime(x.year, x.month, x.day));
  }

  /// El primer minuto en que puede terminar la jornada: el siguiente al del [inicio] (el inicio
  /// queda excluido). En UTC; la hoja de hora ofrece minutos enteros.
  static DateTime primerMinutoDelFin(DateTime inicio) =>
      _alMinuto(inicio).add(const Duration(minutes: 1));

  /// El aviso cuando el reloj del teléfono quedó antes del inicio de la jornada (lo atrasaron a
  /// mano): ningún minuto es válido y nunca se inventa un fin. Lo da el caso de uso y lo muestra
  /// la pantalla "¿A qué hora terminaste?" (decisión del 08/10 en #326).
  static const avisoRelojAtrasado =
      'La hora del teléfono es anterior al inicio de tu jornada. Revisá la fecha y hora del '
      'teléfono y volvé a intentar.';

  /// El aviso cuando la jornada siguiente empezó en el mismo minuto que la que quedó abierta
  /// ([inicio]): entre las dos no cabe ningún minuto, así que no hay hora para cerrarla y nunca se
  /// inventa un fin. Lo muestra la pantalla "¿A qué hora terminaste?" (decisión del agente de
  /// decisiones en #327). `HH:mm` en la zona del dispositivo.
  static String avisoSinHoraPorJornadaSiguiente(DateTime inicio) =>
      'Esta jornada y la siguiente empezaron a la misma hora (${_horaLocal(inicio)}), así que no '
      'hay una hora para cerrarla. Avisale a tu coordinador.';

  /// El último instante válido para el fin: el menor entre [maximoDespuesDelInicio] después del
  /// [inicio], [ahora] (sin horas futuras: HU-JOR-001 y HU-JOR-002) y, si hay, el [inicioSiguiente]
  /// —el inicio de la jornada siguiente del mismo colportor—, para que el fin no pise a la que
  /// sigue y las horas no se cuenten dos veces (HU-JOR-002). Con el [inicioSiguiente] el fin
  /// puede ser igual a él (queda a ras, sin superponerse). En UTC.
  static DateTime topeDelFin({
    required DateTime inicio,
    required DateTime ahora,
    DateTime? inicioSiguiente,
  }) {
    var tope = inicio.toUtc().add(maximoDespuesDelInicio);
    final actual = ahora.toUtc();
    if (actual.isBefore(tope)) tope = actual;
    final siguiente = inicioSiguiente?.toUtc();
    if (siguiente != null && siguiente.isBefore(tope)) tope = siguiente;
    return tope;
  }

  /// `HH:mm` en la zona del dispositivo.
  static String _horaLocal(DateTime instante) {
    final local = instante.toLocal();
    String dosDigitos(int n) => n.toString().padLeft(2, '0');
    return '${dosDigitos(local.hour)}:${dosDigitos(local.minute)}';
  }

  /// [fecha] en UTC, al principio de su minuto.
  static DateTime _alMinuto(DateTime fecha) {
    final utc = fecha.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }
}

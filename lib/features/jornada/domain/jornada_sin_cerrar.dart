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

  /// El último instante válido para el fin: [maximoDespuesDelInicio] después del [inicio] y, como
  /// mucho, [ahora] (sin horas futuras: HU-JOR-001 y HU-JOR-002). En UTC.
  static DateTime topeDelFin({required DateTime inicio, required DateTime ahora}) {
    final maximo = inicio.toUtc().add(maximoDespuesDelInicio);
    final actual = ahora.toUtc();
    return maximo.isBefore(actual) ? maximo : actual;
  }

  /// [fecha] en UTC, al principio de su minuto.
  static DateTime _alMinuto(DateTime fecha) {
    final utc = fecha.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }
}

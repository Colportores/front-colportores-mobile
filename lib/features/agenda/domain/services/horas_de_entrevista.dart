import '../../../../core/error/failure.dart';

/// Las reglas de las horas de una entrevista (vista 39, R·06 y R·07), en un solo lugar.
///
/// Las horas se corrigen de a 5 minutos, como en la jornada (la hoja de la hora es la misma). El
/// tope de duración es el de la jornada que quedó abierta (12 h, `JornadaSinCerrar`): una entrevista
/// más larga es una hora mal puesta, no una entrevista.
abstract final class HorasDeEntrevista {
  static const duracionMaxima = Duration(hours: 12);

  /// Al minuto: el selector ofrece minutos enteros.
  static DateTime alMinuto(DateTime instante) =>
      DateTime(instante.year, instante.month, instante.day, instante.hour, instante.minute);

  /// El último instante válido de la salida: ahora, sin pasar de [duracionMaxima] desde [entrada].
  static DateTime topeDeLaSalida({required DateTime entrada, required DateTime ahora}) {
    final maximo = entrada.add(duracionMaxima);
    return ahora.isBefore(maximo) ? ahora : maximo;
  }

  /// `null` si [entrada] y [salida] valen, o el aviso de por qué no: dice qué pasó y qué hacer.
  static Failure? validar({
    required DateTime entrada,
    required DateTime salida,
    required DateTime ahora,
  }) {
    final campos = <String, String>{};
    // Al minuto: lo que se ve en pantalla es lo que se compara.
    final e = alMinuto(entrada.toLocal());
    final s = alMinuto(salida.toLocal());
    final a = alMinuto(ahora.toLocal());
    if (s.isBefore(e)) {
      campos['salida'] =
          'La salida no puede ser antes de la entrada. Corregí una de las dos horas.';
    } else if (s.isAfter(a)) {
      campos['salida'] = 'La salida no puede ser una hora que todavía no pasó. Elegí otra hora.';
    } else if (s.difference(e) > duracionMaxima) {
      campos['salida'] =
          'Una entrevista no puede durar más de ${duracionMaxima.inHours} horas. '
          'Corregí la entrada o la salida.';
    }
    if (campos.isEmpty) return null;
    return FailureValidacion(campos: campos, mensaje: campos.values.first);
  }
}

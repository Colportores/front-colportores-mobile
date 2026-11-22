/// Las franjas de horario que se recomiendan al agendar una entrevista (08-conceptos-transversales
/// §8.5.2, R-VS05). [codigo] es el valor de `agenda.slot_codigo`, en la DB local y en el cloud.
///
/// El rango va en minutos desde la medianoche, hora del teléfono: desde [desde] inclusive hasta
/// [hasta] exclusive. Entre una franja y la siguiente hay huecos (13:30 a 16:30, por ejemplo): son
/// horas sin franja propia.
enum FranjaHoraria {
  primeraManiana('early_morning', 'Primera mañana', desde: 8 * 60 + 30, hasta: 10 * 60),
  mediaManiana('mid_morning', 'Media mañana', desde: 10 * 60, hasta: 11 * 60 + 30),
  finDeManiana('late_morning', 'Fin de mañana', desde: 11 * 60 + 30, hasta: 13 * 60 + 30),
  primeraTarde('early_afternoon', 'Primera tarde', desde: 16 * 60 + 30, hasta: 18 * 60),
  mediaTarde('mid_afternoon', 'Media tarde', desde: 18 * 60, hasta: 19 * 60 + 15),
  finDeTarde('late_afternoon', 'Fin de tarde', desde: 19 * 60 + 15, hasta: 20 * 60 + 30);

  const FranjaHoraria(this.codigo, this.etiqueta, {required this.desde, required this.hasta});

  /// El valor de `agenda.slot_codigo`.
  final String codigo;

  /// Cómo se llama en pantalla («Primera tarde»).
  final String etiqueta;

  /// Minutos desde la medianoche en que empieza (inclusive).
  final int desde;

  /// Minutos desde la medianoche en que termina (exclusive).
  final int hasta;

  /// El rango como se escribe en pantalla: «16:30 a 18:00».
  String get rango => '${_hora(desde)} a ${_hora(hasta)}';

  /// La franja que se recomienda para la hora [minutoDelDia] (minutos desde la medianoche):
  ///
  /// - la que la contiene;
  /// - si cae en un hueco entre dos franjas, **la que sigue** (14:30 → «Primera tarde»: es lo que
  ///   dibuja el canvas 23A·01 y 23A·05);
  /// - antes de las 08:30, la primera del día;
  /// - `null` si ya pasó la última (a partir de las 20:30): no hay franja que recomendar.
  ///
  /// Es una recomendación: quien agenda la puede aceptar o cambiar.
  static FranjaHoraria? sugeridaPara(int minutoDelDia) {
    for (final f in values) {
      if (minutoDelDia < f.hasta) return f;
    }
    return null;
  }

  /// Inversa de [codigo]; `null` con un código desconocido o `null` (un dato que viene del cloud).
  static FranjaHoraria? desdeCodigo(String? codigo) {
    for (final f in values) {
      if (f.codigo == codigo) return f;
    }
    return null;
  }

  static String _hora(int minutos) =>
      '${(minutos ~/ 60).toString().padLeft(2, '0')}:${(minutos % 60).toString().padLeft(2, '0')}';
}

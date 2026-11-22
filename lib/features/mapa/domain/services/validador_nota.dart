/// Lo que está mal en el texto de una nota.
enum ProblemaNota { vacia }

/// Las reglas del texto de una nota de persona (HU-UBI-012). Dart puro.
abstract final class ValidadorNota {
  /// Límite blando de la HU: 5000 caracteres. Pasarlo **advierte, pero deja guardar**.
  static const largoSuave = 5000;

  static final _invisibles = RegExp(r'[\s\p{Cf}]', unicode: true);

  /// El texto sin espacios ni saltos de línea en los bordes. Lo de adentro no se toca.
  static String limpiar(String? texto) => (texto ?? '').trim();

  /// `null` si la nota sirve. Una nota solo de espacios, saltos de línea o caracteres invisibles es
  /// vacía: no hay nada que recordar.
  static ProblemaNota? problema(String? texto) =>
      (texto ?? '').replaceAll(_invisibles, '').isEmpty ? ProblemaNota.vacia : null;

  /// El aviso de [problema]: qué pasa y qué hacer.
  static String mensaje(ProblemaNota problema) => switch (problema) {
    ProblemaNota.vacia => 'Escribí la nota para poder guardarla.',
  };

  /// Cuántos caracteres Unicode tiene [texto] (no unidades UTF-16).
  static int largo(String? texto) => limpiar(texto).runes.length;

  /// `true` si [texto] pasa el límite blando.
  static bool superaElLimite(String? texto) => largo(texto) > largoSuave;
}

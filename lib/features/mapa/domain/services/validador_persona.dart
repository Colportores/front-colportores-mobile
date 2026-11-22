/// Lo que está mal en el nombre de una persona.
enum ProblemaNombre { vacio, corto }

/// Lo que está mal en el teléfono de una persona.
enum ProblemaTelefono { caracteres, incompleto, sobran }

/// Las reglas de los campos del alta de una persona (HU-UBI-008). Dart puro.
///
/// **Teléfono — pendiente «mapa §2: validación»** (HU-UBI-008, supuesto S20; PREGUNTA del canvas
/// 32A·04): la HU pide validar el formato uruguayo «si tiene `+598`», aceptar los números del exterior
/// que empiezan con `+`, y marcar `abc123` como inválido; el canvas marca `099 12` como incompleto. Lo
/// que no está resuelto es si se exige el formato en los fijos y en lo que no empieza con `+`. Hasta
/// que se decida, [problemaTelefono] rechaza solo lo que la HU y el canvas rechazan y deja pasar el
/// resto: **nunca bloquea un número que puede ser real**. Es el único lugar donde vive la regla.
abstract final class ValidadorPersona {
  /// El nombre se pide con al menos 2 caracteres (HU-UBI-008, «Reglas de negocio»).
  static const largoMinimoNombre = 2;

  /// Dígitos de un celular uruguayo con el 0 inicial (`09X XXX XXX`).
  static const digitosCelular = 9;

  /// Dígitos de un número uruguayo después del `+598`.
  static const digitosConPrefijoPais = 8;

  static final _espacios = RegExp(r'\s+');
  static final _separadores = RegExp(r'[\s().\-]');
  static final _permitido = RegExp(r'^\+?[0-9]+$');

  /// El texto sin espacios en los bordes ni espacios repetidos por dentro.
  static String limpiar(String texto) => texto.trim().replaceAll(_espacios, ' ');

  /// `null` si el nombre sirve. Cuenta caracteres Unicode, no unidades UTF-16.
  static ProblemaNombre? problemaNombre(String? nombre) {
    final largo = limpiar(nombre ?? '').runes.length;
    if (largo == 0) return ProblemaNombre.vacio;
    if (largo < largoMinimoNombre) return ProblemaNombre.corto;
    return null;
  }

  /// `null` si el teléfono sirve. Vacío sirve: es opcional.
  static ProblemaTelefono? problemaTelefono(String? telefono) {
    final compacto = (telefono ?? '').replaceAll(_separadores, '');
    if (compacto.isEmpty) return null;
    if (!_permitido.hasMatch(compacto)) return ProblemaTelefono.caracteres;

    final int esperados;
    final String digitos;
    if (compacto.startsWith('+598')) {
      digitos = compacto.substring(4);
      esperados = digitosConPrefijoPais;
    } else if (compacto.startsWith('09')) {
      digitos = compacto;
      esperados = digitosCelular;
    } else {
      return null;
    }
    if (digitos.length < esperados) return ProblemaTelefono.incompleto;
    if (digitos.length > esperados) return ProblemaTelefono.sobran;
    return null;
  }

  /// El teléfono guardado: sin espacios de más, o `null` si quedó vacío.
  static String? telefonoLimpio(String? telefono) {
    final limpio = limpiar(telefono ?? '');
    return limpio.isEmpty ? null : limpio;
  }

  /// El texto de [problema] (copy a confirmar, salvo «Escribí al menos el nombre.» y «Revisá el
  /// teléfono: le faltan números.», que son los del canvas 32A·03 y 32A·04).
  static String mensajeNombre(ProblemaNombre problema) => switch (problema) {
    ProblemaNombre.vacio => 'Escribí al menos el nombre.',
    ProblemaNombre.corto => 'El nombre necesita al menos 2 letras.',
  };

  static String mensajeTelefono(ProblemaTelefono problema) => switch (problema) {
    ProblemaTelefono.caracteres =>
      'Revisá el teléfono: solo puede tener números, espacios y un + al comienzo.',
    ProblemaTelefono.incompleto => 'Revisá el teléfono: le faltan números.',
    ProblemaTelefono.sobran => 'Revisá el teléfono: le sobran números.',
  };
}

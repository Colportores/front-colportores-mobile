/// Por qué un email no pasa el [ValidadorEmail].
enum ProblemaEmail {
  /// Lleva un carácter que el servidor no acepta en ningún lugar: tilde, ñ, espacio, coma,
  /// comillas, emoji…
  caracterNoPermitido,

  /// Los caracteres son todos válidos, pero la dirección no está completa o está mal armada: falta
  /// la `@`, el dominio o la terminación, hay un `..` o un punto al final.
  incompleto,
}

/// La regla de formato del email, una sola para el login, el registro, el reenvío de la
/// verificación y la recuperación de contraseña (#353).
///
/// Es la del servidor: Supabase Auth valida el formato antes que nada y contesta 400
/// `validation_failed` con el patrón de `<input type="email">` de HTML5. La app lo copia, así no
/// rechaza ningún email que el servidor acepte y frena con el aviso de la pantalla lo que el
/// servidor rechazaría igual:
///
/// - antes de la `@`: letras sin tilde, números y ``.!#$%&'*+/=?^_`{|}~-``;
/// - después: etiquetas separadas por punto, de letras, números y guion (sin empezar ni terminar
///   en guion, de hasta 63 caracteres), así que no hay `..`, ni punto al final;
///
/// y lo que la app ya pedía además: un punto en el dominio, una terminación de 2 o más caracteres
/// y un máximo de [largoMaximo] caracteres.
///
/// El formato no dice si la cuenta existe: la anti-enumeración de la recuperación no cambia. Se
/// valida sobre el email ya normalizado con [normalizar], como hacen los casos de uso (las
/// mayúsculas también pasan: el servidor las acepta y las pasa a minúsculas).
abstract final class ValidadorEmail {
  /// Largo máximo de una dirección (RFC 5321): más que eso no es un email.
  static const int largoMaximo = 254;

  /// El aviso de [ProblemaEmail.caracterNoPermitido], igual en las cuatro pantallas.
  static const String avisoCaracterNoPermitido =
      'Revisá el email: no puede llevar tildes, ñ, espacios ni comas.';

  /// El aviso de un 400 `email_address_invalid` del servidor (la dirección tiene el formato de un
  /// email pero no puede recibir correos: un dominio mal tipeado, uno de prueba…). No dice «ese
  /// dominio no existe»: el servidor lo manda también por otras causas y el aviso no afirma lo que
  /// no sabe. Igual en las cuatro pantallas, en el campo del email.
  static const String avisoDireccionRechazada =
      'Revisá el email: no podemos mandar correos a esa dirección.';

  /// Los caracteres de formato de Unicode (categoría Cf): el espacio de ancho cero `U+200B`, las
  /// marcas de dirección `U+200E`/`U+200F` y `U+202A`–`U+202E`, el guion blando `U+00AD`, el
  /// `U+FEFF`… Se cuelan al pegar un email desde WhatsApp o Gmail y la persona no los ve.
  static final RegExp _invisibles = RegExp(r'\p{Cf}', unicode: true);

  /// Todo lo que puede aparecer en una dirección: lo de antes de la `@`, la `@` y lo de después
  /// (letras, números, punto y guion).
  static final RegExp _caracteresDeUnEmail = RegExp(r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~@-]*$");

  /// Una etiqueta del dominio (HTML5): letras o números en las puntas, guiones solo adentro.
  static final RegExp _etiqueta = RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$');

  /// El email como se valida y se manda al servidor: sin los caracteres invisibles ([_invisibles],
  /// que ninguna dirección que el servidor acepte lleva y la persona no ve), sin espacios
  /// alrededor y en minúsculas (el servidor las guarda así). Un solo lugar para el login, el
  /// registro, el reenvío de la verificación y la recuperación.
  static String normalizar(String email) => email.replaceAll(_invisibles, '').trim().toLowerCase();

  /// Qué le pasa a [email], o `null` si pasa. [email] no puede venir vacío: pedirlo es de cada
  /// pantalla («Ingresá tu email»).
  static ProblemaEmail? problema(String email) {
    if (!_caracteresDeUnEmail.hasMatch(email)) return ProblemaEmail.caracterNoPermitido;
    if (email.length > largoMaximo) return ProblemaEmail.incompleto;

    final arroba = email.indexOf('@');
    if (arroba <= 0 || arroba != email.lastIndexOf('@')) return ProblemaEmail.incompleto;

    final etiquetas = email.substring(arroba + 1).split('.');
    // Un punto en el dominio, etiquetas bien armadas (una vacía es un `..` o un punto de más) y una
    // terminación de 2 o más caracteres.
    if (etiquetas.length < 2 || !etiquetas.every(_etiqueta.hasMatch)) {
      return ProblemaEmail.incompleto;
    }
    if (etiquetas.last.length < 2) return ProblemaEmail.incompleto;

    return null;
  }

  /// El texto del campo para [email], o `null` si pasa: [avisoCaracterNoPermitido] si lleva un
  /// carácter que no va, y [siIncompleto] (el texto de cada pantalla) en los demás casos.
  static String? mensaje(String email, {required String siIncompleto}) {
    return switch (problema(email)) {
      null => null,
      ProblemaEmail.caracterNoPermitido => avisoCaracterNoPermitido,
      ProblemaEmail.incompleto => siIncompleto,
    };
  }
}

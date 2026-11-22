// Dart puro: lo usan tests de dominio y de widget (#353).

/// El aviso de un email con un carácter fuera del patrón, igual en las cuatro pantallas (login,
/// registro, reenvío de la verificación y recuperación). Literal de la decisión del 10/10.
const String avisoCaracterNoPermitido =
    'Revisá el email: no puede llevar tildes, ñ, espacios ni comas.';

/// Emails con un carácter que el servidor no acepta (tilde, ñ, espacio, coma, comillas, emoji…).
/// Los dos primeros son del QA del PR #351.
const List<String> emailsConCaracterNoPermitido = [
  'lucia,@correo.com',
  '"lucia",@correo.com',
  'lucía@correo.com',
  'muñoz@correo.com',
  'lu cia@correo.com',
  'lucia@corréo.com',
  'lucia@correo,com',
  '😀@correo.com',
];

/// Emails que el servidor rechaza por cómo están armados, sin ningún carácter de más: cada pantalla
/// los avisa con su propio texto. Los tres primeros son del QA del PR #351 y del issue #353.
const List<String> emailsIncompletos = [
  'lucia@correo.com.',
  'lucia@correo..com',
  'a@b..co',
  'lucia',
  'lucia@',
  '@correo.com',
  'lucia@correo',
  'lucia@correo.c',
  'lucia@@correo.com',
  'lucia@.correo.com',
  'lucia@-correo.com',
  'lucia@correo-.com',
];

/// Emails raros pero válidos: tienen que pasar (el servidor los acepta). Los dos primeros son los
/// de la decisión del 10/10.
const List<String> emailsValidosRaros = [
  'lucia.perez+campania@correo.com.uy',
  "o'neill@correo.com",
  'a@b.co',
  'lucia_perez-99@mi-correo.com',
  '!#\$%&*+/=?^_`{|}~-@correo.com',
];

/// El aviso de un 400 `email_address_invalid` del servidor, igual en las cuatro pantallas (decisión
/// del 16/10 sobre el PR #354).
const String avisoDireccionRechazada =
    'Revisá el email: no podemos mandar correos a esa dirección.';

/// Caracteres de formato de Unicode (Cf) que se cuelan al pegar un email desde WhatsApp o Gmail y que
/// la persona no ve: las marcas de dirección (`U+200E`), el espacio de ancho cero (`U+200B`), el guion
/// blando, el `U+FEFF`… Los de la decisión del 16/10 sobre el PR #354, más uno de otro bloque
/// (`U+061C`), el `U+180E` y uno fuera del plano básico (`U+E0020`, de las banderas con emoji).
final List<int> invisiblesDeFormato = [
  0x00AD,
  0x061C,
  0x180E,
  for (var c = 0x200B; c <= 0x200F; c++) c,
  for (var c = 0x202A; c <= 0x202E; c++) c,
  for (var c = 0x2060; c <= 0x2064; c++) c,
  for (var c = 0x2066; c <= 0x2069; c++) c,
  0xFEFF,
  0xE0020,
];

/// `U+200E`: el nombre con el que se lo muestra en el nombre de un test.
String codigoUnicode(int c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}';

/// El email al que se normalizan todos los de [emailsConInvisibleEnElMedio] y
/// [emailsConInvisibleAlBorde].
const String emailLimpio = 'lucia@correo.com';

/// [emailLimpio] con el invisible [c] en el medio: en la parte local, pegado a la `@` y en el
/// dominio. Ninguno lo trae `trim()`, ninguno se ve.
List<String> emailsConInvisibleEnElMedio(int c) {
  final i = String.fromCharCode(c);
  return [
    'lu${i}cia@correo.com',
    'lucia$i@correo.com',
    'lucia@${i}correo.com',
    'lucia@co${i}rreo.com',
  ];
}

/// [emailLimpio] con el invisible [c] al borde: al principio, al final, y entre los espacios que sí
/// recorta `trim()` (uno solo no alcanza: el invisible queda adentro de los espacios) y con
/// mayúsculas.
List<String> emailsConInvisibleAlBorde(int c) {
  final i = String.fromCharCode(c);
  return [
    '${i}lucia@correo.com',
    'lucia@correo.com$i',
    ' $i lucia@correo.com $i ',
    '$i Lucia@Correo.COM $i',
  ];
}

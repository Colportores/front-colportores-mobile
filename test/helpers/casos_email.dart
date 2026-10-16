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

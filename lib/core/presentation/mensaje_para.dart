import '../error/failure.dart';

/// El texto que una pantalla muestra para [failure] (decisión de Cristian del 23/09 en #94).
///
/// Sin conexión, cada pantalla dice **para qué** hace falta: "Necesitás conexión para [accion]".
/// En una app offline-first, un "sin conexión" suelto confunde. La capa de datos y el dominio no
/// conocen textos de la UI: [FailureSinConexion] sigue siendo genérico y el texto se arma acá.
/// Cualquier otra falla se muestra con su propio mensaje.
///
/// [accion] es el final de la oración tal cual lo escribe la HU de la pantalla, con su puntuación
/// si la tiene (las HU no son parejas: HU-AUTH-003 termina en punto y HU-AUTH-001/004 no). Así el
/// texto que se ve es el literal del criterio de aceptación.
///
/// Regla para las pantallas nuevas: toda pantalla que necesite red usa esto con su acción y nunca
/// muestra tal cual el mensaje de [FailureSinConexion].
String mensajePara(Failure failure, {required String accion}) => switch (failure) {
  FailureSinConexion() => 'Necesitás conexión para $accion',
  Failure(:final mensaje) => mensaje,
};

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
///
/// Con [noPudimos] ("No pudimos crear tu cuenta."), un error del servidor sin texto propio dice qué
/// pasa y qué hacer ([mensajeDeServidor]) en lugar del genérico.
String mensajePara(Failure failure, {required String accion, String? noPudimos}) =>
    switch (failure) {
      FailureSinConexion() => 'Necesitás conexión para $accion',
      FailureServidor() when noPudimos != null => mensajeDeServidor(failure, noPudimos: noPudimos),
      Failure(:final mensaje) => mensaje,
    };

/// El texto de un error del servidor: todo aviso dice qué pasa y qué hacer, y el mismo caso lleva el
/// mismo texto en cada pantalla (decisión del 29/10 en #542).
///
/// Un [FailureServidor] con texto propio (el rate limit de 429: «Esperá unos minutos…») lo conserva.
/// El que no lo tiene (un código del servidor sin traducción, un 4xx o 5xx cualquiera: trae el
/// genérico, que no dice qué hacer) se muestra como «[noPudimos] Probá de nuevo en unos minutos.».
/// El código técnico nunca llega a la pantalla: queda en el log de la capa de datos.
String mensajeDeServidor(FailureServidor failure, {required String noPudimos}) =>
    failure.mensaje == const FailureServidor().mensaje
    ? '$noPudimos Probá de nuevo en unos minutos.'
    : failure.mensaje;

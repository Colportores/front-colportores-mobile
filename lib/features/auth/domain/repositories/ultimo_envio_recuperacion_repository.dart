/// Cuándo salió el último enlace de recuperación de contraseña pedido desde este teléfono,
/// guardado fuera de la sesión (decisión de Cristian, 02/10,
/// front-colportores-mobile#223; seguimiento #281).
///
/// Sirve para que la espera de 60 s de «Olvidé mi contraseña» (HU-AUTH-004) no se reinicie al salir
/// de la pantalla y volver a entrar. Es **por teléfono, no por correo**: guardarla por correo
/// revelaría si un correo existe. No lleva el correo ni nada de la cuenta, solo la hora.
///
/// Nunca lanza: si el almacén falla, leer devuelve `null` y guardar queda en el log (la espera es
/// una comodidad de la pantalla; el límite de verdad lo aplica el servidor). Las operaciones se
/// ejecutan **en el orden en que se piden**.
abstract interface class UltimoEnvioRecuperacionRepository {
  /// La hora del último envío, en UTC, o `null` si no hay (o no se pudo leer, o el valor está mal
  /// formado).
  Future<DateTime?> leer();

  /// Guarda [cuando] como la hora del último envío, reemplazando la anterior.
  Future<void> guardar(DateTime cuando);
}

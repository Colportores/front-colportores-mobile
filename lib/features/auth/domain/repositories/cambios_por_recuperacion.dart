/// Cuándo este teléfono completó por última vez un cambio de contraseña con un enlace de
/// recuperación (HU-AUTH-005). Es la única pista que tiene la app para distinguir un enlace **ya
/// usado** de uno **vencido**: Supabase manda el mismo `otp_expired` para los dos y el error llega
/// sin el enlace (front-colportores-mobile#247).
///
/// Guarda solo un instante: ningún dato de la cuenta. Nunca lanza: si el almacén falla, la pista se
/// pierde y el enlace se trata como vencido (el caso genérico, con salida para pedir otro).
abstract interface class CambiosPorRecuperacion {
  /// Lo que dura un enlace de recuperación (HU-AUTH-005, «Error -token expirado»: más de 1 h).
  /// Pasado ese tiempo, un enlace ya viejo está vencido de todos modos.
  static const Duration ventana = Duration(hours: 1);

  /// Anota que se acaba de completar un cambio de contraseña con un enlace.
  Future<void> registrar();

  /// Si el último cambio se completó hace [ventana] o menos. Un instante del futuro (el reloj se
  /// atrasó) no cuenta: ante la duda, el enlace se trata como vencido.
  Future<bool> hayUnoReciente();
}

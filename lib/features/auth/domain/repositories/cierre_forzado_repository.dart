import '../entities/cierre_forzado.dart';

/// El motivo y la fecha del último cierre de sesión que la persona no pidió, guardados en el
/// teléfono fuera de la sesión, al lado del último correo (decisión de Cristian, 07/10,
/// front-colportores-mobile#302; amplía la del 01/10, que dejaba guardado únicamente el correo).
///
/// Sirve para que el aviso de «Sesión vencida» (HU-AUTH-007, vista 17) valga en **cada** arranque
/// sin sesión, no solo en el que detectó el cierre: sin esto, quien abre la app otra vez sin señal
/// ve un login común que no explica nada. Se borra cuando la persona entra, con el correo al cerrar
/// sesión a propósito y al borrar los datos locales (HU-AUTH-010, vista 19).
///
/// Nunca lanza: si el almacén falla, leer devuelve `null` y escribir o borrar quedan en el log.
/// Las operaciones se ejecutan **en el orden en que se piden**: un guardado seguido de un borrado
/// deja el cierre borrado, aunque el guardado no haya terminado.
abstract interface class CierreForzadoRepository {
  /// El último cierre guardado, o `null` si no hay (o no se pudo leer, o el valor está mal formado).
  Future<CierreForzado?> leer();

  /// Guarda [cierre], reemplazando el anterior.
  Future<void> guardar(CierreForzado cierre);

  /// Olvida el cierre.
  Future<void> borrar();
}

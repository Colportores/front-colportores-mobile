/// El correo de la última cuenta que estuvo adentro, guardado en el teléfono fuera de la sesión
/// (decisión de Cristian, 01/10): sirve para precargarlo en «Sesión vencida» cuando la app arranca
/// en frío y la sesión ya no está para preguntarle (HU-AUTH-007, vista 17).
///
/// Es **solo** el correo: nada más de la sesión se guarda. Lo único que se guarda al lado es el
/// motivo y la fecha del último cierre que la persona no pidió (`CierreForzadoRepository`, decisión
/// de Cristian, 07/10). Se borra al cerrar la sesión a propósito y al borrar los datos locales
/// (HU-AUTH-010, vista 19).
///
/// Nunca lanza: si el almacén falla, leer devuelve `null` y escribir o borrar quedan en el log.
/// Las operaciones se ejecutan **en el orden en que se piden**: un guardado seguido de un borrado
/// deja el correo borrado, aunque el guardado no haya terminado.
abstract interface class UltimoCorreoRepository {
  /// El correo guardado, o `null` si no hay (o no se pudo leer).
  Future<String?> leer();

  /// Guarda [email] como el de la última cuenta, reemplazando el anterior. Un correo vacío no
  /// guarda nada.
  Future<void> guardar(String email);

  /// Olvida el correo.
  Future<void> borrar();
}

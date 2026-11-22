/// Cuenta las veces que se borraron los datos que el teléfono guardaba de la persona (HU-AUTH-010,
/// «Borrar datos locales»).
///
/// Sirve para no dejar que algo que ya estaba en camino lo vuelva a escribir: quien pide algo lento
/// (una respuesta del servidor) anota la [valor] al pedirlo, y al recibir la respuesta la descarta
/// si ya es otra. La avanza `CustodiaClaveDb.olvidarDatosDelUsuario`, que es quien borra.
final class GeneracionDatosLocales {
  int _valor = 0;

  /// La generación de ahora: sube cada vez que se borran los datos del usuario.
  int get valor => _valor;

  /// Pasa a la generación siguiente.
  void avanzar() => _valor++;
}

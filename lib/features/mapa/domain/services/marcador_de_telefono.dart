/// Abre el marcador del teléfono con un número escrito (HU-UBI-009, «Llamar»). No llama solo: deja el
/// número en el marcador del sistema y la colportora toca el botón verde, así que no hace falta ningún
/// permiso de llamadas.
///
/// Puerto en Dart puro: el adaptador de producción es `MarcadorDeTelefonoCanal`; los tests usan un
/// fake. **Nunca registra el número** (convenciones §7.5).
abstract interface class MarcadorDeTelefono {
  /// `true` si el sistema encontró con qué marcar [numero] (solo dígitos y un `+` al comienzo). Nunca
  /// lanza: `false` si no hay marcador (una tablet, iOS) o no respondió a tiempo.
  Future<bool> marcar(String numero);
}

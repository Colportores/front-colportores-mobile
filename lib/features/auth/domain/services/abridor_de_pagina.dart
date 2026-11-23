/// Abre una dirección web fuera de la app (el navegador del teléfono).
///
/// Puerto del dominio para que quien lo use («términos de uso» del registro) se pruebe sin plataforma.
abstract interface class AbridorDePagina {
  /// `true` si la dirección se abrió; `false` si el teléfono no pudo (sin navegador, rechazo del
  /// sistema). Una falla inesperada de la plataforma sale como excepción: quien llama no puede dar
  /// por hecho que no lanza.
  Future<bool> abrir(Uri direccion);
}

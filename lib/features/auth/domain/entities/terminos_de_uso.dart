/// Los Términos y la Política de Privacidad que acepta la colportora al registrarse (HU-AUTH-001,
/// decisiones de Cristian «Términos» 07/10 y «Texto legal» 21/10).
///
/// El documento es una página web por versión, en GitHub Pages desde el repo público de la
/// organización: se corrige sin sacar otra versión de la app, y el registro guarda qué versión
/// aceptó la persona (`terminos_version` en los metadatos de `signUp`, backend-supabase#109).
abstract final class TerminosDeUso {
  /// La versión que la colportora puede leer hoy desde «términos de uso», y la que el registro manda
  /// como aceptada. El servidor solo guarda una versión publicada (`terminos_versiones_publicadas()`,
  /// hoy `v1`; otra levanta `TC001`).
  static const String versionVigente = 'v1';

  /// Dirección fija de la página de [versionVigente] (repo `Colportores/terminos`).
  static final Uri direccion = Uri.parse('https://colportores.github.io/terminos/$versionVigente/');

  /// Aviso cuando no hay conexión para abrir la página (texto del issue #386).
  static const String avisoSinConexion = 'Necesitás conexión para leer los términos.';

  /// Aviso cuando hay conexión pero el teléfono no pudo abrir la página (sin navegador, o se
  /// rechazó la apertura). Texto propuesto, a confirmar: dice qué pasó y qué hacer.
  static const String avisoNoSeAbrio =
      'No pudimos abrir los términos. Probá de nuevo en unos minutos.';
}

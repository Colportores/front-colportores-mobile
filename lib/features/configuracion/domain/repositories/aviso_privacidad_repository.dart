/// Qué cuentas escondieron el aviso «Estos datos solo viven en tu celular. Nunca se suben a la
/// nube.» con «No volver a mostrar» (decisión de Cristian, 23/10, «Aviso privado»;
/// front-colportores-mobile#445 y #447).
///
/// Es una preferencia **por cuenta** y **del teléfono**: no sube a ningún lado. Es una sola para los
/// dos lugares donde sale el aviso (el alta de persona, HU-UBI-008, y las notas, HU-UBI-012); se
/// vuelve a encender desde Configuración, «Mostrar el aviso de privacidad».
///
/// Lo que no se sabe se trata como «visible»: ante la duda el aviso se muestra (el principio de
/// privacidad del proyecto), nunca se esconde por una lectura fallida.
abstract interface class AvisoPrivacidadRepository {
  /// Si la cuenta [cuentaId] escondió el aviso. `false` si nunca lo escondió **o si no se pudo leer**
  /// (nunca lanza).
  Future<bool> estaOculto(String cuentaId);

  /// Anota que [cuentaId] no quiere ver el aviso. No toca a las demás cuentas. Lanza si no pudo
  /// guardarlo: quien lo pide avisa a la persona y deja el aviso a la vista.
  Future<void> ocultar(String cuentaId);

  /// Vuelve a encender el aviso de [cuentaId]. Lanza si no pudo guardarlo.
  Future<void> mostrar(String cuentaId);
}

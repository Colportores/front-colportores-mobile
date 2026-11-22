/// Si el asistente de recuperación del primer arranque (HU-SYNC-006, vista 34) ya se resolvió para
/// un usuario en este teléfono: recuperó sus datos o eligió «Empezar sin recuperar».
///
/// Por usuario: otra persona que entre en el mismo teléfono ve el asistente la primera vez.
abstract interface class RecuperacionResueltaRepository {
  /// `true` si [usuarioId] ya resolvió el asistente. Lanza si el almacén no se deja leer: la raíz
  /// de la app no ofrece la recuperación sobre algo que no pudo mirar.
  Future<bool> estaResuelta(String usuarioId);

  /// Anota que [usuarioId] resolvió el asistente. Nunca lanza: si no se pudo guardar, el asistente
  /// se vuelve a ofrecer en el arranque siguiente (no se pierde nada).
  Future<void> marcarResuelta(String usuarioId);

  /// Quita la marca de [usuarioId]: el asistente vuelve a ofrecerse en el próximo arranque de la raíz,
  /// mientras el teléfono siga sin datos. Es lo que deja «Recuperar mi respaldo» de Configuración
  /// antes de reiniciar la app (decisión de Cristian, 04/11, «Motor vivo»). Lanza si no se pudo
  /// quitar: sin la marca quitada, el reinicio abriría la app de siempre.
  Future<void> desmarcarResuelta(String usuarioId);
}

/// Sin almacén: el asistente nunca se ofrece. Es el valor por defecto (tests y demo); `main.dart`
/// lo reemplaza por el almacén seguro.
final class RecuperacionNuncaSeOfrece implements RecuperacionResueltaRepository {
  const RecuperacionNuncaSeOfrece();

  @override
  Future<bool> estaResuelta(String usuarioId) async => true;

  @override
  Future<void> marcarResuelta(String usuarioId) async {}

  @override
  Future<void> desmarcarResuelta(String usuarioId) async {}
}

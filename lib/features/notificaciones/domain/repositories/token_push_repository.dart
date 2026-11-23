/// Por qué el servidor no guardó el token de push.
sealed class TokenPushException implements Exception {
  const TokenPushException();
}

/// Sin red, con el servidor cortado a mitad o sin contestar a tiempo.
final class TokenPushSinConexionException extends TokenPushException {
  const TokenPushSinConexionException();

  @override
  String toString() => 'TokenPushSinConexionException';
}

/// El servidor contestó con un error (o no hay sesión: `42501`).
final class TokenPushServidorException extends TokenPushException {
  const TokenPushServidorException({this.codigo});

  /// El SQLSTATE de la falla, si lo hubo.
  final String? codigo;

  @override
  String toString() => 'TokenPushServidorException($codigo)';
}

/// Dónde se guarda a qué teléfono mandarle los avisos (`usuario.fcm_token`, HU-NOT-001).
///
/// Se escribe con la función del servidor `registrar_mi_token_push`, nunca por la cola de
/// sincronización ni con un PATCH a la fila (ADR-013, decisión de Cristian del 04/11, «Token push»).
abstract interface class TokenPushRepository {
  /// Deja [token] como el teléfono de quien tiene la sesión (un token pertenece a una sola cuenta: el
  /// servidor se lo quita a cualquier otra). `null` lo borra (cierre de sesión). Lanza una
  /// [TokenPushException].
  Future<void> registrar(String? token);
}

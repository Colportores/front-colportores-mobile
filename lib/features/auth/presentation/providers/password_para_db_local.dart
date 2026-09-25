import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'password_para_db_local.g.dart';

/// La contraseña con la que el usuario acaba de entrar, guardada en memoria hasta que la DB local
/// quede lista (HU-AUTH-009, #27).
///
/// La preparación de la DB corre después del login, en otra pantalla, y la necesita para envolver
/// la DEK con Argon2id (ADR-006): sin ella no hay recuperación por contraseña. Se guarda solo al
/// entrar con email y contraseña (login y registro con sesión), se usa en cada intento de la
/// preparación —un reintento después de, por ejemplo, liberar espacio también tiene que armar el
/// envoltorio— y se olvida en cuanto la DB queda lista o la sesión termina. Nunca va a disco ni a
/// un log: [toString] no la incluye.
final class PasswordParaDbLocal {
  String? _password;

  /// La contraseña guardada, o `null` si no hay (login con Google, sesión restaurada).
  String? get actual => _password;

  /// Guarda [password] para la próxima preparación de la DB.
  void recordar(String password) => _password = password;

  /// La olvida: la DB ya quedó lista o la sesión terminó.
  void olvidar() => _password = null;

  @override
  String toString() => 'PasswordParaDbLocal(${_password == null ? 'vacía' : 'guardada'})';
}

/// Uno solo para toda la app: lo escribe `SesionNotifier` al entrar y lo lee la preparación de la
/// DB local (`PreparacionDbLocalNotifier`).
@Riverpod(keepAlive: true)
PasswordParaDbLocal passwordParaDbLocal(Ref ref) => PasswordParaDbLocal();

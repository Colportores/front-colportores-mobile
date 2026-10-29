import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/enlace_recuperacion.dart';

/// Confirmación de la recuperación de contraseña (HU-AUTH-005): lo que pasa después de que el
/// usuario abre el enlace que pidió en HU-AUTH-004.
abstract interface class RecuperacionPasswordRepository {
  /// Cada enlace de recuperación que llega a la app, válido o no.
  Stream<EnlaceRecuperacion> get enlaces;

  /// El `usuario_id` de la cuenta que abrió el enlace, o `null` si no hay sesión de recuperación.
  String? get usuarioId;

  /// Fija [nueva] como contraseña de la cuenta, con la sesión que abrió el enlace.
  /// `Left(FailureEnlaceRecuperacionVencido)` si esa sesión ya no sirve.
  ///
  /// Reintentar es idempotente: si un intento se cortó sin respuesta y el servidor sí lo había
  /// aceptado, el reintento con la misma contraseña da `Right` (no "igual a la anterior").
  Future<Either<Failure, Unit>> actualizarPassword(String nueva);

  /// Revoca todas las sesiones de la cuenta, en todos los dispositivos, incluida la de este.
  Future<Either<Failure, Unit>> cerrarTodasLasSesiones();

  /// `true` si [cerrarTodasLasSesiones] no llegó a revocar (sin respuesta o con error): la
  /// contraseña cambió pero los otros teléfonos pueden seguir con su sesión. Solo en memoria y atada
  /// a la cuenta que cambió la contraseña; baja cuando [cerrarOtrasSesionesPendientes] lo logra.
  bool get otrasSesionesSinCerrar;

  /// Si quedó pendiente la revocación de las otras sesiones de la cuenta [usuarioId], la reintenta
  /// (scope `others`, sin tocar la sesión de este teléfono: se llama con la sesión nueva ya
  /// abierta). Sin pendiente, o si la pendiente es de otra cuenta, no hace nada y la marca queda
  /// como está. Si falla, la marca sigue para el próximo login de esa cuenta.
  Future<Either<Failure, Unit>> cerrarOtrasSesionesPendientes(String usuarioId);

  /// Suelta la sesión de recuperación sin cambiar nada (el usuario salió de la pantalla): el enlace
  /// no puede dejar la app con una sesión iniciada sin contraseña.
  Future<Either<Failure, Unit>> abandonar();
}

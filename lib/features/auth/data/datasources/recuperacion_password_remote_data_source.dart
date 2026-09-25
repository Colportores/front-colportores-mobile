import '../../domain/entities/enlace_recuperacion.dart';
import 'auth_remote_data_source.dart';

/// Origen remoto de la confirmación de recuperación de contraseña (HU-AUTH-005). La implementación
/// real es `AuthRemoteDataSourceSupabase`; la de tests y demo, `RecuperacionPasswordEnMemoria`.
///
/// Como [AuthRemoteDataSource], **lanza** [AuthRemoteException] y el repositorio las traduce.
abstract interface class RecuperacionPasswordRemoteDataSource {
  /// Cada enlace de recuperación que llega a la app: [EnlaceRecuperacion.valido] cuando el enlace
  /// dejó una sesión de recuperación, [EnlaceRecuperacion.vencido] cuando no se pudo canjear (y
  /// [EnlaceRecuperacion.sinConexion] si fue por falta de red: el enlace sigue sirviendo).
  Stream<EnlaceRecuperacion> get enlacesRecuperacion;

  /// Fija [nueva] con la sesión de recuperación. Lanza [PasswordIgualALaAnteriorException],
  /// [PasswordDebilException], [SesionDeRecuperacionVencidaException], [SinConexionException] o
  /// [ServidorException].
  Future<void> actualizarPassword(String nueva);

  /// Revoca todas las sesiones de la cuenta (scope global), incluida la de este cliente.
  Future<void> cerrarTodasLasSesiones();

  /// Suelta la sesión de recuperación de este cliente sin cambiar la contraseña.
  Future<void> abandonarRecuperacion();
}

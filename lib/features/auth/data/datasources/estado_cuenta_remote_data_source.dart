import '../../domain/entities/estado_cuenta.dart';

/// De dónde sale el estado de la cuenta (HU-AUTH-008): el backend, por la RPC `estado_cuenta()` de
/// Supabase (ADR-013: sin BFF). La RPC identifica al usuario por el JWT de la sesión.
///
/// Lanza `SinConexionException` sin red y `ServidorException` si el servidor responde con error
/// (`auth_remote_data_source.dart`).
abstract interface class EstadoCuentaRemoteDataSource {
  Future<EstadoCuenta> consultar();
}

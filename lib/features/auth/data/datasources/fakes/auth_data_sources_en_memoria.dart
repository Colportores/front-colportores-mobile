import '../../models/sesion_model.dart';
import '../auth_local_data_source.dart';
import '../auth_remote_data_source.dart';

/// Origen remoto en memoria: acepta un conjunto fijo de credenciales.
///
/// Sirve para desarrollar la UI contra un backend inexistente (igual que `FakeSyncTransport` en el
/// contrato de sync) y para los tests del repositorio. **No es código de producción**: `main.dart`
/// lo reemplaza por la implementación Supabase en Sprint 3.
final class AuthRemoteDataSourceEnMemoria implements AuthRemoteDataSource {
  AuthRemoteDataSourceEnMemoria({
    required Map<String, String> credenciales,
    this.simularSinConexion = false,
    this.cuentasPendientes = const {},
    DateTime Function()? ahora,
  }) : _credenciales = Map.unmodifiable(credenciales),
       _ahora = ahora ?? DateTime.now;

  /// Cuenta de demo para correr la app sin backend.
  factory AuthRemoteDataSourceEnMemoria.demo() =>
      AuthRemoteDataSourceEnMemoria(credenciales: const {'demo@colportores.app': 'demo1234'});

  final Map<String, String> _credenciales;
  final Set<String> cuentasPendientes;
  final DateTime Function() _ahora;

  /// Si es `true`, toda llamada lanza [SinConexionException].
  bool simularSinConexion;

  int llamadasCerrarSesion = 0;

  @override
  Future<SesionModel> iniciarSesion({required String email, required String password}) async {
    if (simularSinConexion) throw const SinConexionException();
    if (cuentasPendientes.contains(email)) throw const CuentaPendienteException();
    if (_credenciales[email] != password) throw const CredencialesInvalidasException();

    return SesionModel(
      usuarioId: _uuidDesde(email),
      email: email,
      accessToken: 'token-en-memoria-${email.hashCode}',
      expiraEn: _ahora().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> cerrarSesion(String accessToken) async {
    if (simularSinConexion) throw const SinConexionException();
    llamadasCerrarSesion++;
  }

  /// UUID determinístico (con forma de v7) a partir del email, solo para el fake.
  static String _uuidDesde(String email) {
    final h = email.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    return '01920000-0000-7000-8000-0000$h';
  }
}

/// Persistencia local en memoria. Se pierde al reiniciar la app — a propósito.
final class AuthLocalDataSourceEnMemoria implements AuthLocalDataSource {
  SesionModel? _sesion;

  @override
  Future<SesionModel?> leerSesion() async => _sesion;

  @override
  Future<void> guardarSesion(SesionModel sesion) async => _sesion = sesion;

  @override
  Future<void> borrarSesion() async => _sesion = null;
}

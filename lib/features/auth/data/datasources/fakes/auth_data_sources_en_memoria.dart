import '../../../domain/entities/usuario.dart';
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
  }) : _credenciales = Map.of(credenciales),
       _ahora = ahora ?? DateTime.now;

  /// Cuenta de demo para correr la app sin backend.
  factory AuthRemoteDataSourceEnMemoria.demo() =>
      AuthRemoteDataSourceEnMemoria(credenciales: const {'demo@colportores.app': 'demo1234'});

  /// Mutable a propósito: `registrar` agrega credenciales nuevas para que la demo pueda
  /// registrarse y loguearse a continuación.
  final Map<String, String> _credenciales;
  final Set<String> cuentasPendientes;
  final DateTime Function() _ahora;

  /// Perfiles registrados en este fake (HU-AUTH-001). Solo en memoria: la persistencia local
  /// del perfil depende de la DB cifrada (#6, bloqueado) y no está implementada.
  final Map<String, Usuario> _usuarios = {};

  Map<String, Usuario> get usuariosRegistrados => Map.unmodifiable(_usuarios);

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
  Future<SesionModel> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async {
    if (simularSinConexion) throw const SinConexionException();
    if (_credenciales.containsKey(email)) throw const EmailYaRegistradoException();

    _credenciales[email] = password;
    final usuarioId = _uuidDesde(email);
    _usuarios[email] = Usuario(
      id: usuarioId,
      nombre: nombre,
      apellido: apellido,
      cedula: cedula,
      email: email,
    );

    return SesionModel(
      usuarioId: usuarioId,
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

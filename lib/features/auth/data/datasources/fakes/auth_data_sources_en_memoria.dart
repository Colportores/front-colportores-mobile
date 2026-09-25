import 'dart:async';

import '../../../domain/entities/motivo_expiracion.dart';
import '../../../domain/entities/politica_sesion.dart';
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
    this.requiereVerificacionAlRegistrar = false,
    DateTime Function()? ahora,
  }) : _credenciales = Map.of(credenciales),
       _ahora = ahora ?? DateTime.now;

  /// Cuenta de demo para correr la app sin backend.
  factory AuthRemoteDataSourceEnMemoria.demo() =>
      AuthRemoteDataSourceEnMemoria(credenciales: const {'demo@colportores.app': 'demo1234'});

  /// Mutable a propósito: `registrar` agrega credenciales nuevas para que la demo pueda
  /// registrarse y loguearse a continuación.
  final Map<String, String> _credenciales;
  final DateTime Function() _ahora;

  /// Si es `true`, `registrar` crea la cuenta pero devuelve `null` en vez de sesión — simula
  /// Supabase con "Confirm email" activo (HU-AUTH-002), para poder probar ese flujo sin backend.
  final bool requiereVerificacionAlRegistrar;

  /// Perfiles registrados en este fake (HU-AUTH-001). Solo en memoria: la persistencia local
  /// del perfil depende de la DB cifrada (#6, bloqueado) y no está implementada.
  final Map<String, Usuario> _usuarios = {};

  Map<String, Usuario> get usuariosRegistrados => Map.unmodifiable(_usuarios);

  /// Si es `true`, toda llamada lanza [SinConexionException].
  bool simularSinConexion;

  int llamadasCerrarSesion = 0;

  /// Cuentas registradas con `requiereVerificacionAlRegistrar` que todavía no confirmaron el
  /// email — [confirmarEmail] las saca de acá.
  final Set<String> _pendientesDeVerificar = {};

  static const String _mensajeEmailNoConfirmado =
      'Tenés que verificar tu correo antes de entrar. Revisá tu bandeja.';

  @override
  Future<SesionModel> iniciarSesion({required String email, required String password}) async {
    if (simularSinConexion) throw const SinConexionException();
    if (_credenciales[email] != password) throw const CredencialesInvalidasException();
    // El orden importa: como en Supabase real, una contraseña incorrecta da credenciales
    // inválidas primero — recién con la contraseña bien se ve si falta confirmar el email.
    if (_pendientesDeVerificar.contains(email)) {
      throw const ServidorException(mensaje: _mensajeEmailNoConfirmado);
    }

    return SesionModel(
      usuarioId: _uuidDesde(email),
      email: email,
      accessToken: 'token-en-memoria-${email.hashCode}',
      expiraEn: PoliticaSesion.expiraEn(_ahora()),
    );
  }

  /// Cuántas veces se solicitó recuperación de contraseña (HU-AUTH-004), por email. Se registra
  /// igual exista o no la cuenta —anti-enumeración—: el fake no puede filtrar esa diferencia.
  final Map<String, int> solicitudesRecuperacionPorEmail = {};

  /// Si no es `null`, toda llamada a [solicitarRecuperacionPassword] lo lanza en vez de
  /// registrar la solicitud — para simular un rate limit u otro error de Supabase.
  AuthRemoteException? fallaAlSolicitarRecuperacion;

  @override
  Future<void> solicitarRecuperacionPassword(String email) async {
    if (simularSinConexion) throw const SinConexionException();
    if (fallaAlSolicitarRecuperacion != null) throw fallaAlSolicitarRecuperacion!;
    solicitudesRecuperacionPorEmail.update(email, (n) => n + 1, ifAbsent: () => 1);
  }

  /// Cuántas veces se llamó a [registrar] — para probar la guarda de doble tap de RegistroPage.
  int llamadasRegistrar = 0;

  /// Si no es `null`, [registrar] no sigue hasta que el test lo complete — para que un segundo
  /// toque ocurra mientras el primero todavía está en vuelo (sin esto el fake resuelve
  /// instantáneo y no hay ventana de carrera real que probar).
  Completer<void>? demoraRegistrar;

  @override
  Future<SesionModel?> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async {
    llamadasRegistrar++;
    await demoraRegistrar?.future;
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

    if (requiereVerificacionAlRegistrar) {
      _pendientesDeVerificar.add(email);
      return null;
    }

    return SesionModel(
      usuarioId: usuarioId,
      email: email,
      accessToken: 'token-en-memoria-${email.hashCode}',
      expiraEn: PoliticaSesion.expiraEn(_ahora()),
    );
  }

  /// Cuenta fija con la que "entra" Google en la demo (no hay navegador ni deep link acá).
  static const String emailGoogle = 'google@colportores.app';

  int llamadasIniciarSesionConGoogle = 0;

  @override
  Future<SesionModel> iniciarSesionConGoogle() async {
    if (simularSinConexion) throw const SinConexionException();
    llamadasIniciarSesionConGoogle++;
    return SesionModel(
      usuarioId: _uuidDesde(emailGoogle),
      email: emailGoogle,
      accessToken: 'token-google-en-memoria',
      expiraEn: PoliticaSesion.expiraEn(_ahora()),
      entraConPassword: false,
    );
  }

  /// Si es `true`, [renovarSesion] lanza [SesionRevocadaException] (el servidor ya no acepta la
  /// sesión, HU-AUTH-007).
  bool sesionRevocadaEnElServidor = false;

  /// Si está, [renovarSesion] espera a que el test la complete.
  Completer<void>? demoraAlRenovar;

  int llamadasRenovarSesion = 0;
  int _renovaciones = 0;

  @override
  Future<SesionModel> renovarSesion() async {
    llamadasRenovarSesion++;
    await demoraAlRenovar?.future;
    if (simularSinConexion) throw const SinConexionException();
    if (sesionRevocadaEnElServidor) throw const SesionRevocadaException();
    _renovaciones++;
    return SesionModel(
      usuarioId: _uuidDesde('demo@colportores.app'),
      email: 'demo@colportores.app',
      accessToken: 'token-renovado-$_renovaciones',
      expiraEn: PoliticaSesion.expiraEn(_ahora()),
    );
  }

  final _expiraciones = StreamController<MotivoExpiracion>.broadcast();

  @override
  Stream<MotivoExpiracion> get expiraciones => _expiraciones.stream;

  /// Simula que el proveedor terminó la sesión por su cuenta (HU-AUTH-007).
  void simularExpiracion(MotivoExpiracion motivo) => _expiraciones.add(motivo);

  /// Simula que al arrancar se descartó una sesión guardada por 30 días sin uso.
  bool vencidaPorInactividadAlArrancar = false;

  @override
  bool tomarVencimientoPorInactividad() {
    final vencio = vencidaPorInactividadAlArrancar;
    vencidaPorInactividadAlArrancar = false;
    return vencio;
  }

  /// El fake no persiste nada entre reinicios: la sesión "recordada" es siempre `null`.
  @override
  Future<SesionModel?> obtenerSesionActual() async => null;

  /// El fake no tiene un cliente que renueve el token: siempre `null` (se usa la guardada).
  @override
  SesionModel? sesionEnElCliente() => null;

  @override
  Future<void> cerrarSesion(String accessToken) async {
    if (simularSinConexion) throw const SinConexionException();
    llamadasCerrarSesion++;
  }

  /// Tokens revocados con [revocarSesion], en orden. El scope no se registra porque el puerto lo
  /// fija: siempre es solo esa sesión (el adaptador de Supabase pasa `SignOutScope.local`).
  final List<String> revocaciones = [];

  @override
  Future<void> revocarSesion(String accessToken) async {
    if (simularSinConexion) throw const SinConexionException();
    revocaciones.add(accessToken);
  }

  /// Simula que el usuario tocó el link de verificación del correo: [iniciarSesion] deja de
  /// lanzar el "falta confirmar" para esta cuenta. Sin efecto si no se registró con
  /// `requiereVerificacionAlRegistrar`.
  void confirmarEmail(String email) => _pendientesDeVerificar.remove(email);

  /// Cuántas veces se reenvió el email de verificación (HU-AUTH-002), por email.
  final Map<String, int> reenviosPorEmail = {};

  /// Si no es `null`, toda llamada a [reenviarVerificacion] lo lanza en vez de reenviar — para
  /// simular el rate limit de Supabase (~2 emails/hora sin SMTP propio).
  AuthRemoteException? fallaAlReenviar;

  @override
  Future<void> reenviarVerificacion(String email) async {
    if (simularSinConexion) throw const SinConexionException();
    if (fallaAlReenviar != null) throw fallaAlReenviar!;
    reenviosPorEmail.update(email, (n) => n + 1, ifAbsent: () => 1);
  }

  final _erroresVerificacionController = StreamController<void>.broadcast();

  @override
  Stream<void> get erroresVerificacionEmail => _erroresVerificacionController.stream;

  /// Simula que el deep link de verificación volvió con un enlace vencido o ya usado.
  void simularEnlaceVerificacionInvalido() => _erroresVerificacionController.add(null);

  final _verificacionExitosaController = StreamController<void>.broadcast();

  @override
  Stream<void> get verificacionesExitosas => _verificacionExitosaController.stream;

  /// Simula que el deep link de verificación volvió válido (issue #84): confirma el email —igual
  /// que [confirmarEmail]— y emite el evento de éxito.
  void simularEnlaceVerificacionExitoso(String email) {
    confirmarEmail(email);
    _verificacionExitosaController.add(null);
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

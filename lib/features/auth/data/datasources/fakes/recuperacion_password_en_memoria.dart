import 'dart:async';

import '../../../domain/entities/enlace_recuperacion.dart';
import '../auth_remote_data_source.dart';
import '../recuperacion_password_remote_data_source.dart';

/// [RecuperacionPasswordRemoteDataSource] en memoria, para tests y para la demo sin backend.
///
/// **No es código de producción.** Sin Supabase no hay deep links: los enlaces se simulan con
/// [simularEnlace].
final class RecuperacionPasswordEnMemoria implements RecuperacionPasswordRemoteDataSource {
  RecuperacionPasswordEnMemoria({this._passwordActual = 'Secreto123'});

  final _enlaces = StreamController<EnlaceRecuperacion>.broadcast();
  String _passwordActual;
  bool _haySesionDeRecuperacion = false;

  /// Si es `true`, las operaciones de red lanzan [SinConexionException].
  bool simularSinConexion = false;

  /// Si no es `null`, [actualizarPassword] lo lanza.
  AuthRemoteException? fallaAlActualizar;

  /// Si no es `null`, [cerrarTodasLasSesiones] lo lanza.
  AuthRemoteException? fallaAlCerrarSesiones;

  /// Si está, [actualizarPassword] espera a que el test la complete (estado "guardando").
  Completer<void>? demoraAlActualizar;

  /// Si es `true`, la próxima [actualizarPassword] fija la contraseña pero lanza
  /// [SinConexionException], como si la respuesta se hubiera perdido en el camino. Una sola vez.
  bool pierdeLaRespuestaAlActualizar = false;

  /// Contraseñas fijadas, en orden.
  final List<String> actualizaciones = [];

  int sesionesCerradas = 0;
  int abandonos = 0;

  /// La contraseña que tiene la cuenta ahora.
  String get passwordActual => _passwordActual;

  /// Simula que llegó un enlace de recuperación. Uno válido deja una sesión de recuperación.
  void simularEnlace(EnlaceRecuperacion enlace) {
    _haySesionDeRecuperacion = enlace == EnlaceRecuperacion.valido;
    _enlaces.add(enlace);
  }

  /// Simula que la sesión de recuperación venció mientras la pantalla estaba abierta.
  void vencerSesionDeRecuperacion() => _haySesionDeRecuperacion = false;

  @override
  Stream<EnlaceRecuperacion> get enlacesRecuperacion => _enlaces.stream;

  @override
  Future<void> actualizarPassword(String nueva) async {
    await demoraAlActualizar?.future;
    if (simularSinConexion) throw const SinConexionException();
    if (fallaAlActualizar case final falla?) throw falla;
    if (!_haySesionDeRecuperacion) throw const SesionDeRecuperacionVencidaException();
    if (nueva == _passwordActual) throw const PasswordIgualALaAnteriorException();
    _passwordActual = nueva;
    actualizaciones.add(nueva);
    if (pierdeLaRespuestaAlActualizar) {
      pierdeLaRespuestaAlActualizar = false;
      throw const SinConexionException();
    }
  }

  @override
  Future<void> cerrarTodasLasSesiones() async {
    if (simularSinConexion) throw const SinConexionException();
    if (fallaAlCerrarSesiones case final falla?) throw falla;
    _haySesionDeRecuperacion = false;
    sesionesCerradas++;
  }

  @override
  Future<void> abandonarRecuperacion() async {
    _haySesionDeRecuperacion = false;
    abandonos++;
  }
}

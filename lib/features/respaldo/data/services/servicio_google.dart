import 'package:equatable/equatable.dart';

/// Una cuenta de Google que autorizó el respaldo. No es el usuario de la app.
final class CuentaGoogle extends Equatable {
  const CuentaGoogle({required this.id, required this.email});

  final String id;
  final String email;

  @override
  List<Object?> get props => [id, email];
}

/// Google conectó la cuenta pero el token no trae el permiso de Drive: la persona desmarcó la
/// casilla. No se da por conectado.
final class PermisoDriveNoConcedido implements Exception {
  const PermisoDriveNoConcedido();

  @override
  String toString() => 'PermisoDriveNoConcedido';
}

/// Lo que la app usa de `google_sign_in`, y nada más. Puerto: el repositorio no conoce el plugin,
/// así que se prueba sin teléfono ni cuenta de Google.
///
/// Los fallos del plugin salen como `GoogleSignInException` (cancelar, configuración, etc.); los de
/// red, como las excepciones de red de siempre (`SocketException`, `http.ClientException`,
/// `TimeoutException`).
abstract interface class ServicioGoogle {
  /// Abre la pantalla de Google (elegir cuenta y dar el permiso de Drive) y devuelve la cuenta
  /// elegida. Lanza [PermisoDriveNoConcedido] si el permiso no vino.
  Future<CuentaGoogle> conectar();

  /// El token de acceso de Drive, pedido sin abrir ninguna pantalla. `null` si Google ya no tiene
  /// el permiso (la persona lo quitó desde su cuenta, o hace falta que lo vuelva a dar).
  Future<String?> tokenSilencioso();

  /// Le pide a Google que retire el permiso de la app. Los archivos del Drive no se tocan.
  Future<void> desconectar();
}

/// Sin identificadores de cliente de Google (`--dart-define=GOOGLE_SERVER_CLIENT_ID`): no hay
/// forma de conectar. Es lo que corre en los tests, en CI y en la demo sin registrar la app. Nadie
/// puede tener Drive conectado, así que lo demás no hace nada.
final class ServicioGoogleSinConfigurar implements ServicioGoogle {
  const ServicioGoogleSinConfigurar();

  @override
  Future<CuentaGoogle> conectar() => Future<CuentaGoogle>.error(
    StateError('Google no está configurado (GOOGLE_SERVER_CLIENT_ID)'),
  );

  @override
  Future<String?> tokenSilencioso() async => null;

  @override
  Future<void> desconectar() async {}
}

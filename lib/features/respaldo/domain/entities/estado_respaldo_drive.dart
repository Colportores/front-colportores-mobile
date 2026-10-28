import 'package:equatable/equatable.dart';

/// Cómo está el respaldo en el Google Drive de una persona (HU-SYNC-004, vista 16 «Cuenta Drive»).
///
/// Es por usuario de la app: otra persona que use el mismo teléfono no hereda el Drive de esta. La
/// cuenta de Google no es la de la app (la app entra con correo y contraseña): se usa solo para el
/// respaldo.
sealed class EstadoRespaldoDrive extends Equatable {
  const EstadoRespaldoDrive();

  /// Cuántos respaldos puede hacer hoy la app: solo si está conectada y con permiso.
  bool get respaldaAhora => this is DriveConectada;

  @override
  List<Object?> get props => const [];
}

/// Nunca se conectó, o se desconectó (16D·01).
final class DriveSinConectar extends EstadoRespaldoDrive {
  const DriveSinConectar();
}

/// Una cuenta de Google que el respaldo ya usa.
sealed class DriveConCuenta extends EstadoRespaldoDrive {
  const DriveConCuenta({required this.email, required this.cuentaId});

  /// Correo de la cuenta de Google (no el de la app). Solo para mostrarlo; no va a los logs.
  final String email;

  /// Identificador de la cuenta de Google, para saber si es la misma que se autorizó.
  final String cuentaId;

  @override
  List<Object?> get props => [email, cuentaId];
}

/// Conectada y con permiso vigente (16D·04).
final class DriveConectada extends DriveConCuenta {
  const DriveConectada({required super.email, required super.cuentaId});
}

/// La persona le quitó el permiso a la app desde su cuenta de Google (16D·06): los respaldos están
/// frenados hasta que vuelva a conectar. Los archivos que ya estaban en su Drive siguen ahí.
final class DrivePermisoRevocado extends DriveConCuenta {
  const DrivePermisoRevocado({required super.email, required super.cuentaId});
}

/// El Drive de la persona no tiene espacio (16D·10): el último respaldo no se guardó. El permiso
/// sigue vigente; no hay nada que reconectar.
final class DriveSinEspacio extends DriveConCuenta {
  const DriveSinEspacio({required super.email, required super.cuentaId});
}

/// Lo que devuelve una conexión lograda.
final class ConexionDrive extends Equatable {
  const ConexionDrive({required this.estado, required this.primerRespaldoHecho});

  final DriveConectada estado;

  /// Si ya se hizo el primer respaldo en el momento (16D·04: «Hicimos el primer respaldo en tu
  /// Drive»). `false` cuando todavía no hay quién lo haga o falló: la conexión vale igual y el
  /// aviso solo promete el respaldo de la noche.
  final bool primerRespaldoHecho;

  @override
  List<Object?> get props => [estado, primerRespaldoHecho];
}

import 'dart:async';

import '../../../domain/entities/estado_cuenta.dart';
import '../auth_remote_data_source.dart';
import '../estado_cuenta_remote_data_source.dart';

/// [EstadoCuentaRemoteDataSource] en memoria, para tests y para la demo sin backend (la cuenta
/// demo está activa). **No es código de producción.**
final class EstadoCuentaEnMemoria implements EstadoCuentaRemoteDataSource {
  EstadoCuentaEnMemoria({this.estado = EstadoCuenta.activa});

  /// Lo que responde el "backend". Un test lo cambia para simular que el coordinador asignó (o
  /// que un administrador suspendió) la cuenta.
  EstadoCuenta estado;

  /// Si es `true`, [consultar] lanza [SinConexionException].
  bool simularSinConexion = false;

  /// Si no es `null`, [consultar] lo lanza.
  AuthRemoteException? falla;

  /// Si está, [consultar] espera a que el test la complete.
  Completer<void>? demora;

  int consultas = 0;

  @override
  Future<EstadoCuenta> consultar() async {
    consultas++;
    await demora?.future;
    if (simularSinConexion) throw const SinConexionException();
    if (falla case final falla?) throw falla;
    return estado;
  }
}

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/logging/app_logger.dart';

/// Por qué el servidor no contestó la deuda con la casa editora.
sealed class DeudaRemotaException implements Exception {
  const DeudaRemotaException();
}

/// Sin red, con el servidor cortado a mitad o sin contestar a tiempo.
final class DeudaSinConexionException extends DeudaRemotaException {
  const DeudaSinConexionException();

  @override
  String toString() => 'DeudaSinConexionException';
}

/// El servidor contestó con un error (o no hay sesión: `42501`).
final class DeudaServidorException extends DeudaRemotaException {
  const DeudaServidorException({this.codigo});

  /// El SQLSTATE de la falla, si lo hubo.
  final String? codigo;

  @override
  String toString() => 'DeudaServidorException($codigo)';
}

/// De dónde sale la deuda: el RPC del servidor.
abstract interface class DeudaConLaCasaRemoteDataSource {
  /// El JSON que contesta `mi_deuda_con_la_casa_editora()`. Lanza una [DeudaRemotaException].
  Future<Object?> leer();
}

/// [DeudaConLaCasaRemoteDataSource] real: llama al RPC `mi_deuda_con_la_casa_editora()` con la sesión
/// de `supabase_flutter` (ADR-013, sin BFF; backend-supabase 0164). No recibe parámetros: el servidor
/// usa al usuario del JWT, así que cada colportor ve solo lo suyo. Al log va solo el SQLSTATE.
final class DeudaConLaCasaSupabase implements DeudaConLaCasaRemoteDataSource {
  /// [llamarRpc] es la costura de los tests: devuelve lo que contesta el RPC.
  DeudaConLaCasaSupabase(this._llamarRpc, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  /// Sobre el cliente de Supabase de la app.
  DeudaConLaCasaSupabase.conCliente(SupabaseClient cliente, {AppLogger? logger})
    : this(() async => await cliente.rpc<Object?>('mi_deuda_con_la_casa_editora'), logger: logger);

  final Future<Object?> Function() _llamarRpc;
  final AppLogger _log;

  @override
  Future<Object?> leer() async {
    try {
      return await _llamarRpc();
    } on PostgrestException catch (e) {
      _log.warn(LogModulo.net, 'DEUDA_CASA_RPC_FAIL', 'el RPC de la deuda respondió con error', {
        'code': e.code,
      });
      throw DeudaServidorException(codigo: e.code);
    } on AuthException catch (e) {
      if (e is AuthRetryableFetchException) throw const DeudaSinConexionException();
      _log.warn(LogModulo.net, 'DEUDA_CASA_RPC_FAIL', 'la sesión no sirvió para leer la deuda', {
        'code': e.code,
      });
      throw const DeudaServidorException(codigo: '42501');
    } on Object catch (e) {
      if (_esFallaDeRed(e)) throw const DeudaSinConexionException();
      rethrow;
    }
  }

  static bool _esFallaDeRed(Object e) =>
      e is IOException || e is http.ClientException || e is TimeoutException;
}

/// Sin Supabase configurado (tests, demo) no hay de dónde traer la deuda: como si no hubiera red.
final class DeudaConLaCasaSinServidor implements DeudaConLaCasaRemoteDataSource {
  const DeudaConLaCasaSinServidor();

  @override
  Future<Object?> leer() => Future<Object?>.error(const DeudaSinConexionException());
}

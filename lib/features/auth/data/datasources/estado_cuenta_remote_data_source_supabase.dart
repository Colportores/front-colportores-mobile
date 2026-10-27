import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/estado_cuenta.dart';
import 'auth_remote_data_source.dart';
import 'estado_cuenta_remote_data_source.dart';

/// [EstadoCuentaRemoteDataSource] real: llama a la RPC `estado_cuenta()` de Supabase con la sesión
/// de `supabase_flutter` (HU-AUTH-008, ADR-013: sin BFF). La RPC no recibe parámetros: lee al
/// usuario del JWT y contesta un texto, `ACTIVA`, `PENDIENTE_ASIGNACION` o `SUSPENDIDA`. El estado
/// lo decide el servidor, nunca la app.
///
/// Traducción de las fallas (sin PII en el log: solo códigos):
/// - red caída, corte o tiempo agotado → [SinConexionException];
/// - `42501` (sin sesión válida) → `ServidorException(status: 401)`;
/// - `P0002` (perfil no encontrado) → `ServidorException(status: 404)`;
/// - cualquier otro error del servidor, o un valor que la app no conoce → [ServidorException].
final class EstadoCuentaSupabase implements EstadoCuentaRemoteDataSource {
  /// [llamarRpc] es la costura de los tests: devuelve lo que contesta `estado_cuenta()`.
  EstadoCuentaSupabase(this._llamarRpc, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  /// Sobre el cliente de Supabase de la app.
  EstadoCuentaSupabase.conCliente(SupabaseClient cliente, {AppLogger? logger})
    : this(() async => await cliente.rpc<Object?>('estado_cuenta'), logger: logger);

  final Future<Object?> Function() _llamarRpc;
  final AppLogger _log;

  @override
  Future<EstadoCuenta> consultar() async {
    final Object? respuesta;
    try {
      respuesta = await _llamarRpc();
    } on PostgrestException catch (e) {
      throw _traducir(e);
    } on AuthException catch (e) {
      if (e is AuthRetryableFetchException) throw const SinConexionException();
      _log.warn(LogModulo.auth, 'ESTADO_CUENTA_FAIL', 'la sesión no sirvió para consultar', {
        'code': e.code,
      });
      throw const ServidorException(status: 401);
    } on Object catch (e) {
      if (_esFallaDeRed(e)) throw const SinConexionException();
      rethrow;
    }
    return _aEstado(respuesta);
  }

  EstadoCuenta _aEstado(Object? respuesta) {
    switch (respuesta) {
      case 'ACTIVA':
        return EstadoCuenta.activa;
      case 'PENDIENTE_ASIGNACION':
        return EstadoCuenta.pendienteAsignacion;
      case 'SUSPENDIDA':
        return EstadoCuenta.suspendida;
    }
    // Un valor nuevo del servidor no se adivina: ante la duda no se afirma nada de la cuenta
    // (la pantalla muestra «No pudimos consultar el estado de tu cuenta» y deja reintentar).
    _log.warn(LogModulo.auth, 'ESTADO_CUENTA_FAIL', 'la RPC contestó un valor desconocido', {
      'tipo': respuesta.runtimeType.toString(),
    });
    throw const ServidorException(status: 200);
  }

  ServidorException _traducir(PostgrestException e) {
    _log.warn(LogModulo.auth, 'ESTADO_CUENTA_FAIL', 'la RPC estado_cuenta respondió con error', {
      'code': e.code,
    });
    return switch (e.code) {
      '42501' => const ServidorException(status: 401),
      'P0002' => const ServidorException(status: 404),
      final String codigo => ServidorException(status: int.tryParse(codigo)),
      null => const ServidorException(),
    };
  }

  /// Sin red, con el servidor cortado a mitad o sin contestar a tiempo.
  static bool _esFallaDeRed(Object e) =>
      e is IOException || e is http.ClientException || e is TimeoutException;
}

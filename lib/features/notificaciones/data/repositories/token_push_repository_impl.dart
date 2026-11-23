import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/repositories/token_push_repository.dart';

/// [TokenPushRepository] real, con la sesión de `supabase_flutter` (ADR-013, sin BFF;
/// backend-supabase 0165).
///
/// Llama a `rpc('registrar_mi_token_push', {p_token})`: el servidor guarda el token en la fila de
/// quien llama (`null` lo borra). Sin sesión contesta `42501`; un token con forma inválida, `23514`.
///
/// Al log va solo el SQLSTATE: nunca el token. Si el servidor no contesta en [tope] se da por perdido
/// (sin conexión).
final class TokenPushSupabase implements TokenPushRepository {
  /// [registrarRpc] es la costura de los tests: la llamada al RPC.
  TokenPushSupabase({required this.registrarRpc, this.tope = topeDeLaLlamada, AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  /// Sobre el cliente de Supabase de la app.
  factory TokenPushSupabase.conCliente(SupabaseClient cliente, {AppLogger? logger}) =>
      TokenPushSupabase(
        registrarRpc: (token) async {
          await cliente.rpc<Object?>('registrar_mi_token_push', params: {'p_token': token});
        },
        logger: logger,
      );

  /// Cuánto se espera una respuesta del servidor antes de contarla como sin conexión.
  static const topeDeLaLlamada = Duration(seconds: 20);

  final Future<void> Function(String? token) registrarRpc;
  final AppLogger _log;
  final Duration tope;

  @override
  Future<void> registrar(String? token) async {
    try {
      await registrarRpc(token).timeout(tope);
    } on PostgrestException catch (e) {
      _log.warn(LogModulo.net, 'TOKEN_PUSH_RPC', 'el servidor respondió con error', {
        'code': e.code,
      });
      throw TokenPushServidorException(codigo: e.code);
    } on AuthException catch (e) {
      if (e is AuthRetryableFetchException) throw const TokenPushSinConexionException();
      _log.warn(LogModulo.net, 'TOKEN_PUSH_RPC', 'la sesión no sirvió para la llamada', {
        'code': e.code,
      });
      throw const TokenPushServidorException(codigo: '42501');
    } on Object catch (e) {
      if (_esFallaDeRed(e)) throw const TokenPushSinConexionException();
      rethrow;
    }
  }

  static bool _esFallaDeRed(Object e) =>
      e is IOException || e is http.ClientException || e is TimeoutException;
}

/// [TokenPushRepository] en memoria: el default de los tests y de la app sin Supabase (demo).
/// **No es código de producción**: sin servidor no hay a dónde guardar, solo recuerda lo que se le
/// dijo.
class TokenPushEnMemoria implements TokenPushRepository {
  /// Si no es `null`, [registrar] lanza esto y no guarda nada.
  TokenPushException? falla;

  /// Si no es `null`, [registrar] espera a que se complete (el servidor todavía no contestó).
  Completer<void>? demorado;

  /// Cada token que se mandó a guardar (`null` = vaciar), en el orden en que llegó; también los que
  /// fallaron.
  final List<String?> pedidos = [];

  /// Lo que el servidor tiene guardado ahora.
  String? guardado;

  @override
  Future<void> registrar(String? token) async {
    pedidos.add(token);
    await demorado?.future;
    final f = falla;
    if (f != null) throw f;
    guardado = token;
  }
}

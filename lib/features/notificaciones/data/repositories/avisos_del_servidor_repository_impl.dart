import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/avisos_del_servidor.dart';
import '../../domain/repositories/avisos_del_servidor_repository.dart';

/// [AvisosDelServidorRepository] real, con la sesión de `supabase_flutter` (ADR-013, sin BFF;
/// backend-supabase 0166).
///
/// - Lee `usuario.notif_preferences` de la fila propia (un `select`; la política de lectura deja ver
///   solo la de quien llama).
/// - Guarda con `rpc('guardar_mis_preferencias_de_avisos', {p_preferencias: {...}})`, el objeto entero.
///   El servidor rechaza una forma inválida con `23514`.
///
/// Al log va solo el SQLSTATE: nunca las preferencias. Si el servidor no contesta en [tope] se da por
/// perdido (sin conexión): una conexión a medias no puede dejar la pantalla cargando para siempre ni un
/// guardado «en curso» sin fin.
final class AvisosDelServidorSupabase implements AvisosDelServidorRepository {
  /// [leerFila] y [guardarRpc] son la costura de los tests: lo que contesta el `select` de la fila
  /// propia y la llamada al RPC.
  AvisosDelServidorSupabase({
    required this.leerFila,
    required this.guardarRpc,
    this.tope = topeDeLaLlamada,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  /// Sobre el cliente de Supabase de la app.
  factory AvisosDelServidorSupabase.conCliente(SupabaseClient cliente, {AppLogger? logger}) =>
      AvisosDelServidorSupabase(
        leerFila: () async {
          final usuarioId = cliente.auth.currentUser?.id;
          if (usuarioId == null) {
            throw const PostgrestException(message: 'sin sesión', code: '42501');
          }
          final fila = await cliente
              .from('usuario')
              .select('notif_preferences')
              .eq('id', usuarioId)
              .maybeSingle();
          return fila?['notif_preferences'];
        },
        guardarRpc: (preferencias) async {
          await cliente.rpc<Object?>(
            'guardar_mis_preferencias_de_avisos',
            params: {'p_preferencias': preferencias},
          );
        },
        logger: logger,
      );

  /// Cuánto se espera una respuesta del servidor antes de contarla como sin conexión.
  static const topeDeLaLlamada = Duration(seconds: 20);

  final Future<Object?> Function() leerFila;
  final Future<void> Function(Map<String, Object?> preferencias) guardarRpc;
  final AppLogger _log;
  final Duration tope;

  @override
  Future<AvisosDelServidor> leer() async {
    final Object? json = await _llamar('AVISOS_LEER', leerFila);
    return AvisosDelServidor.desdeJson(json);
  }

  @override
  Future<void> guardar(AvisosDelServidor avisos) =>
      _llamar('AVISOS_GUARDAR', () => guardarRpc(avisos.aJson()));

  Future<T> _llamar<T>(String operacion, Future<T> Function() llamada) async {
    try {
      return await llamada().timeout(tope);
    } on PostgrestException catch (e) {
      _log.warn(LogModulo.net, operacion, 'el servidor respondió con error', {'code': e.code});
      throw AvisosServidorException(codigo: e.code);
    } on AuthException catch (e) {
      if (e is AuthRetryableFetchException) throw const AvisosSinConexionException();
      _log.warn(LogModulo.net, operacion, 'la sesión no sirvió para la llamada', {'code': e.code});
      throw const AvisosServidorException(codigo: '42501');
    } on Object catch (e) {
      if (_esFallaDeRed(e)) throw const AvisosSinConexionException();
      rethrow;
    }
  }

  static bool _esFallaDeRed(Object e) =>
      e is IOException || e is http.ClientException || e is TimeoutException;
}

/// [AvisosDelServidorRepository] en memoria: el default de los tests y de la app sin Supabase
/// (demo). **No es código de producción**: sin servidor no hay a dónde guardar, solo recuerda lo que
/// se le dijo mientras la app está abierta.
class AvisosDelServidorEnMemoria implements AvisosDelServidorRepository {
  AvisosDelServidorEnMemoria({this.avisos = const AvisosDelServidor()});

  AvisosDelServidor avisos;

  /// Si no es `null`, [leer] lanza esto.
  AvisosDelServidorException? fallaAlLeer;

  /// Si no es `null`, [guardar] lanza esto y no guarda nada.
  AvisosDelServidorException? fallaAlGuardar;

  /// Si no es `null`, [leer] espera a que se complete (el servidor todavía no contestó).
  Completer<void>? lecturaDemorada;

  /// Si no es `null`, [guardar] espera a que se complete.
  Completer<void>? guardadoDemorado;

  /// Cada objeto que se mandó a guardar, en el orden en que llegó (también los que fallaron).
  final List<Map<String, Object?>> guardados = [];

  /// Cuántas veces se leyó.
  int lecturas = 0;

  @override
  Future<AvisosDelServidor> leer() async {
    lecturas++;
    await lecturaDemorada?.future;
    final falla = fallaAlLeer;
    if (falla != null) throw falla;
    return avisos;
  }

  @override
  Future<void> guardar(AvisosDelServidor nuevos) async {
    guardados.add(nuevos.aJson());
    await guardadoDemorado?.future;
    final falla = fallaAlGuardar;
    if (falla != null) throw falla;
    avisos = nuevos;
  }
}

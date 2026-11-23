// HU-NOT-001 / #414: el token se guarda con `registrar_mi_token_push` (backend-supabase 0165), no por
// PATCH ni por la cola de sync. Importa supabase_flutter: flutter_test.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/token_push_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/token_push_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/logger_mudo.dart';

TokenPushSupabase _repo(Future<void> Function(String?) rpc, {AppLogger? logger}) =>
    TokenPushSupabase(
      registrarRpc: rpc,
      tope: const Duration(seconds: 5),
      logger: logger ?? loggerMudo(),
    );

final class _Salida extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  test('manda el token a la función tal cual', () async {
    String? recibido = 'nada';
    await _repo((t) async => recibido = t).registrar('fcm-abc');
    expect(recibido, 'fcm-abc');
  });

  test('null llega como null: vacía el token al cerrar sesión', () async {
    String? recibido = 'nada';
    await _repo((t) async => recibido = t).registrar(null);
    expect(recibido, isNull);
  });

  for (final (nombre, error, sinConexion) in <(String, Object, bool)>[
    ('sin red (SocketException)', const SocketException('sin ruta'), true),
    ('cliente HTTP caído', http.ClientException('cortado'), true),
    ('la sesión no se pudo renovar por la red', AuthRetryableFetchException(message: 'x'), true),
    ('tiempo agotado', TimeoutException('x'), true),
    ('sin sesión (42501)', const PostgrestException(message: 'x', code: '42501'), false),
    (
      'token con forma inválida (23514)',
      const PostgrestException(message: 'x', code: '23514'),
      false,
    ),
    ('sesión vencida', const AuthException('vencida'), false),
  ]) {
    test('$nombre se traduce', () {
      expect(
        _repo((_) => Future<void>.error(error)).registrar('t'),
        throwsA(
          sinConexion ? isA<TokenPushSinConexionException>() : isA<TokenPushServidorException>(),
        ),
      );
    });
  }

  test('el SQLSTATE queda en la falla', () async {
    try {
      await _repo(
        (_) => Future<void>.error(const PostgrestException(message: 'x', code: '23514')),
      ).registrar('t');
      fail('debía lanzar');
    } on TokenPushServidorException catch (e) {
      expect(e.codigo, '23514');
    }
  });

  test('un servidor que no contesta se cuenta como sin conexión', () {
    expect(
      TokenPushSupabase(
        registrarRpc: (_) => Completer<void>().future,
        tope: const Duration(milliseconds: 10),
        logger: loggerMudo(),
      ).registrar('t'),
      throwsA(isA<TokenPushSinConexionException>()),
    );
  });

  test('al log no va el token', () async {
    final salida = _Salida();
    final logger = AppLogger(
      logger: Logger(output: salida, printer: SimplePrinter()),
    );
    await expectLater(
      _repo(
        (_) => Future<void>.error(const PostgrestException(message: 'fcm-secreto', code: '42501')),
        logger: logger,
      ).registrar('fcm-secreto'),
      throwsA(isA<TokenPushServidorException>()),
    );
    expect(salida.lineas.join('\n'), isNot(contains('fcm-secreto')));
  });

  test('el repositorio en memoria recuerda lo último y lo vacía con null', () async {
    final r = TokenPushEnMemoria();
    await r.registrar('a');
    await r.registrar(null);
    expect(r.pedidos, ['a', null]);
    expect(r.guardado, isNull);
  });
}

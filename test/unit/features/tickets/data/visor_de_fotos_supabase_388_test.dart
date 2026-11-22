// Ver la foto de un ticket por el enlace firmado de `foto-ticket` (acción `ver`, HU-COB-009, #388):
// qué contesta cada código de la función y que nunca lanza.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/features/tickets/data/services/servidor_de_fotos_supabase.dart'
    show RespuestaDeLaFuncion;
import 'package:colportores_mobile/features/tickets/data/services/visor_de_fotos_supabase.dart';
import 'package:colportores_mobile/features/tickets/domain/services/visor_de_fotos.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

void main() {
  late List<Map<String, Object?>> pedidos;

  VisorDeFotosSupabase visor({RespuestaDeLaFuncion? responde, Object? falla}) {
    pedidos = [];
    return VisorDeFotosSupabase((cuerpo) async {
      pedidos.add(cuerpo);
      if (falla != null) throw falla;
      return responde ?? (status: 200, cuerpo: const <String, Object?>{});
    }, logger: loggerMudo());
  }

  test('pide la acción «ver» con el id del ticket y devuelve el enlace', () async {
    final v = visor(
      responde: (
        status: 200,
        cuerpo: {
          'accion': 'ver',
          'metodo': 'GET',
          'url': 'https://r2.example/bucket/u-1/t-1.jpg?X-Amz-Signature=abc',
          'cabeceras': <String, Object?>{},
        },
      ),
    );

    final r = await v.ver('t-1');

    expect(pedidos, [
      {'accion': 'ver', 'ticketId': 't-1'},
    ]);
    expect(r, isA<FotoEnLaNube>());
    expect(
      (r as FotoEnLaNube).url,
      Uri.parse('https://r2.example/bucket/u-1/t-1.jpg?X-Amz-Signature=abc'),
    );
  });

  test('una respuesta 200 sin enlace utilizable no es una foto', () async {
    for (final cuerpo in <Map<String, Object?>>[
      {},
      {'url': 42},
      {'url': 'sin esquema'},
    ]) {
      final r = await visor(responde: (status: 200, cuerpo: cuerpo)).ver('t-1');
      expect(r, isA<FotoNoDisponible>(), reason: '$cuerpo');
      expect((r as FotoNoDisponible).sinRed, isFalse);
    }
  });

  test('410: pasaron los 4 meses y la foto ya no está', () async {
    final r = await visor(
      responde: (
        status: 410,
        cuerpo: {
          'error': {'codigo': 'foto_vencida', 'mensaje': 'La foto ya no está.'},
        },
      ),
    ).ver('t-1');

    expect(r, isA<FotoVencida>());
  });

  test(
    '404 sin_foto: el ticket todavía no tiene foto; 404 de otra cosa, no se pudo traer',
    () async {
      final sinFoto = await visor(
        responde: (
          status: 404,
          cuerpo: {
            'error': {'codigo': 'sin_foto'},
          },
        ),
      ).ver('t-1');
      final noEncontrado = await visor(
        responde: (
          status: 404,
          cuerpo: {
            'error': {'codigo': 'ticket_no_encontrado'},
          },
        ),
      ).ver('t-1');
      final sinCuerpo = await visor(responde: (status: 404, cuerpo: const {})).ver('t-1');

      expect(sinFoto, isA<SinFotoParaVer>());
      expect(noEncontrado, isA<FotoNoDisponible>());
      expect(sinCuerpo, isA<FotoNoDisponible>());
    },
  );

  test('una falla del servidor (401, 500, 502, 503) no es la foto: se puede reintentar', () async {
    for (final status in [401, 500, 502, 503]) {
      final r = await visor(responde: (status: status, cuerpo: const {})).ver('t-1');
      expect(r, isA<FotoNoDisponible>(), reason: '$status');
      expect((r as FotoNoDisponible).sinRed, isFalse, reason: '$status');
    }
  });

  test(
    'sin red (socket, cliente http o tiempo agotado) lo dice; cualquier otra excepción, no',
    () async {
      for (final falla in <Object>[
        const SocketException('sin red'),
        http.ClientException('sin red'),
        TimeoutException('tarda'),
      ]) {
        final r = await visor(falla: falla).ver('t-1');
        expect(r, isA<FotoNoDisponible>(), reason: '$falla');
        expect((r as FotoNoDisponible).sinRed, isTrue, reason: '$falla');
      }
      final otra = await visor(falla: StateError('raro')).ver('t-1');
      expect(otra, isA<FotoNoDisponible>());
      expect((otra as FotoNoDisponible).sinRed, isFalse);
    },
  );
}

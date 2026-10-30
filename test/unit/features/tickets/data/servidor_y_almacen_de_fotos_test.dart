// La subida de la foto por el enlace firmado y el almacén en disco (HU-COB-007, #426).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/features/tickets/data/services/almacen_de_fotos_en_disco.dart';
import 'package:colportores_mobile/features/tickets/data/services/servidor_de_fotos_supabase.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/services/puertos_de_fotos.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/tickets_falsos.dart';

void main() {
  group('ServidorDeFotosSupabase', () {
    final enlace = <String, Object?>{
      'accion': 'subir',
      'metodo': 'PUT',
      'url': 'https://r2.example/bucket/u-1/t-1.jpg?X-Amz-Signature=abc',
      'ruta': 'u-1/t-1.jpg',
      'cabeceras': {'Content-Type': 'image/jpeg', 'Content-Length': '1000'},
      'venceEn': '2026-10-30T15:10:00.000Z',
    };

    late List<Map<String, Object?>> pedidosDeEnlace;
    late List<({Uri url, Map<String, String> cabeceras, int bytes})> puts;

    ServidorDeFotosSupabase servidor({
      RespuestaDeLaFuncion Function()? funcion,
      int status = 200,
      Object? falla,
      Object? fallaPut,
      String? usuario = 'u-1',
    }) {
      pedidosDeEnlace = [];
      puts = [];
      return ServidorDeFotosSupabase(
        (cuerpo) async {
          pedidosDeEnlace.add(cuerpo);
          if (falla != null) throw falla;
          return funcion?.call() ?? (status: 200, cuerpo: enlace);
        },
        (url, cabeceras, bytes) async {
          puts.add((url: url, cabeceras: cabeceras, bytes: bytes.length));
          if (fallaPut != null) throw fallaPut;
          return status;
        },
        () => usuario,
        logger: loggerMudo(),
      );
    }

    Future<ResultadoDeSubidaDeFoto> subir(ServidorDeFotosSupabase s) =>
        s.subir(ticketId: 't-1', tipo: TipoDeImagen.jpeg, bytes: fotoDePrueba());

    test(
      'pide el enlace con el tipo y el tamaño de la foto y hace el PUT con las cabeceras exactas '
      'que devolvió la función',
      () async {
        final r = await subir(servidor());

        expect(r, isA<FotoSubida>().having((f) => f.ruta, 'ruta', 'u-1/t-1.jpg'));
        expect(pedidosDeEnlace.single, {
          'accion': 'subir',
          'ticketId': 't-1',
          'tipoDeImagen': 'image/jpeg',
          'bytes': 1000,
        });
        expect(puts.single.url.host, 'r2.example');
        expect(puts.single.cabeceras, {'Content-Type': 'image/jpeg', 'Content-Length': '1000'});
        expect(puts.single.bytes, 1000);
      },
    );

    test('409 foto_ya_subida: la foto ya está, con la ruta de la sesión y el ticket', () async {
      final r = await subir(servidor(funcion: () => (status: 409, cuerpo: const {})));

      expect(r, isA<FotoYaEstaba>().having((f) => f.ruta, 'ruta', 'u-1/t-1.jpg'));
      expect(puts, isEmpty);
    });

    test('409 sin sesión para armar la ruta: se reintenta', () async {
      final r = await subir(
        servidor(funcion: () => (status: 409, cuerpo: const {}), usuario: null),
      );

      expect(r, isA<SubidaFallida>().having((f) => f.reintentable, 'reintentable', isTrue));
    });

    test('lo que el servidor rechaza para siempre no se reintenta: 400, 410, 413, 415', () async {
      for (final (status, codigo) in [
        (400, 'pedido_invalido'),
        (410, 'foto_vencida'),
        (413, 'foto_muy_pesada'),
        (415, 'tipo_no_aceptado'),
      ]) {
        final r = await subir(servidor(funcion: () => (status: status, cuerpo: const {})));
        expect(
          r,
          isA<SubidaFallida>()
              .having((f) => f.codigo, 'codigo', codigo)
              .having((f) => f.reintentable, 'reintentable', isFalse),
          reason: '$status',
        );
      }
    });

    test(
      'lo que puede salir más tarde se reintenta: 401, 404 (la fila no llegó), 502, 503',
      () async {
        for (final (status, codigo) in [
          (401, 'sin_sesion'),
          (404, 'ticket_no_encontrado'),
          (502, 'servidor_502'),
          (503, 'servidor_503'),
        ]) {
          final r = await subir(servidor(funcion: () => (status: status, cuerpo: const {})));
          expect(
            r,
            isA<SubidaFallida>()
                .having((f) => f.codigo, 'codigo', codigo)
                .having((f) => f.reintentable, 'reintentable', isTrue),
            reason: '$status',
          );
          expect(puts, isEmpty);
        }
      },
    );

    test('sin red al pedir el enlace o al hacer el PUT: se reintenta con código «red»', () async {
      for (final s in [
        servidor(falla: const SocketException('sin red')),
        servidor(fallaPut: http.ClientException('cortado')),
        servidor(fallaPut: TimeoutException('lento')),
      ]) {
        final r = await subir(s);
        expect(
          r,
          isA<SubidaFallida>()
              .having((f) => f.codigo, 'codigo', 'red')
              .having((f) => f.reintentable, 'reintentable', isTrue),
        );
      }
    });

    test('una excepción inesperada no escapa: es un fallo reintentable', () async {
      final r = await subir(servidor(falla: StateError('raro')));

      expect(r, isA<SubidaFallida>().having((f) => f.codigo, 'codigo', 'inesperado'));
    });

    test(
      'el PUT que R2 rechaza (403 por enlace vencido) se reintenta con un enlace nuevo',
      () async {
        final r = await subir(servidor(status: 403));

        expect(
          r,
          isA<SubidaFallida>()
              .having((f) => f.codigo, 'codigo', 'put_403')
              .having((f) => f.reintentable, 'reintentable', isTrue),
        );
      },
    );

    test('una respuesta sin url, ruta o cabeceras no se sube', () async {
      final r = await subir(servidor(funcion: () => (status: 200, cuerpo: const {'ruta': 'x'})));

      expect(r, isA<SubidaFallida>().having((f) => f.codigo, 'codigo', 'respuesta_invalida'));
      expect(puts, isEmpty);
    });
  });

  group('AlmacenDeFotosEnDisco', () {
    late Directory base;
    late AlmacenDeFotosEnDisco almacen;

    setUp(() {
      base = Directory.systemTemp.createTempSync('fotos_tickets_');
      almacen = AlmacenDeFotosEnDisco(base.path);
    });
    tearDown(() => base.deleteSync(recursive: true));

    test('guarda la foto como <ticket>.<ext> dentro de tickets/ y la lee igual', () async {
      final ruta = await almacen.guardar('t-1', TipoDeImagen.png, fotoDePrueba(500));

      expect(ruta, endsWith('t-1.png'));
      expect(ruta, contains('tickets'));
      expect(await almacen.leer(ruta), fotoDePrueba(500));
      expect(Directory(File(ruta).parent.path).listSync().whereType<File>(), hasLength(1));
    });

    test('guardar otra vez pisa la copia anterior y no deja el temporal', () async {
      await almacen.guardar('t-1', TipoDeImagen.jpeg, fotoDePrueba(10));
      final ruta = await almacen.guardar('t-1', TipoDeImagen.jpeg, fotoDePrueba(20));

      expect((await almacen.leer(ruta))!.length, 20);
      expect(File(ruta).parent.listSync().map((e) => e.path.split(Platform.pathSeparator).last), [
        't-1.jpg',
      ]);
    });

    test('leer un archivo que no está es null y borrar uno que no está no falla', () async {
      final inexistente =
          '${base.path}${Platform.pathSeparator}tickets${Platform.pathSeparator}x.jpg';

      expect(await almacen.leer(inexistente), isNull);
      await almacen.borrar(inexistente);
    });

    test('borrar saca el archivo', () async {
      final ruta = await almacen.guardar('t-1', TipoDeImagen.webp, Uint8List.fromList([1, 2, 3]));

      await almacen.borrar(ruta);

      expect(File(ruta).existsSync(), isFalse);
    });
  });
}

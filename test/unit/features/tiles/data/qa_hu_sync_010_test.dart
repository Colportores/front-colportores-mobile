// QA de HU-SYNC-010 (front-colportores-mobile#191): los criterios de aceptación de la HU y lo que
// pide el QA-HU-SYNC-010 («reintentos, fallos parciales, offline y consistencia del payload»),
// de punta a punta con los adaptadores reales (HTTP con `Range`, archivos del disco, SHA-256,
// manifiesto y canal nativo del espacio libre). Lo único falso es el servidor (`MockClient`), el
// lado nativo del canal y la conectividad.
//
// Trazabilidad (criterio de la HU → dónde se prueba):
// - «Descarga exitosa» (Wi-Fi, progreso, checksum, disponible para el mapa offline) → grupo
//   «descarga exitosa».
// - «Sin espacio» («Espacio insuficiente - faltan X MB») → grupo «sin espacio».
// - «Pausa y resume» (se pierde el Wi-Fi, al volver sigue con HTTP Range) → grupo «pausa y
//   resume».
// - «Solo Wi-Fi por defecto» → grupo «solo Wi-Fi por defecto».
// - «Eliminar un paquete individual» → grupo «eliminar de a uno».
// - «Checksum inválido descarta el archivo» → grupo «checksum inválido» (el archivo que se daña ya
//   registrado, en `composicion_tiles_test.dart`, «al arrancar la app (reconciliar)»).
// - Fallos parciales, reintentos y consistencia del payload → grupos «fallos parciales» y «el
//   archivo no es lo que dice el catálogo».
// La lógica con puertos falsos (todos los bordes del descargador) está en
// `domain/services/descargador_*_test.dart`; la de la vista, en `test/widget/mapa/` y
// `test/widget/mapas_offline_page_test.dart`.
//
// No prueba contra el bucket real.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tiles/data/composicion_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/estado_descarga.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../../helpers/tiles_falsos.dart';

const _archivoMvd = 'ciudad-mvd-3f9c1a2b7d44.pmtiles';
const _archivoSalto1 = 'ciudad-salto-9a1b2c3d4e5f-p1.pmtiles';
const _archivoSalto2 = 'ciudad-salto-0f1e2d3c4b5a-p2.pmtiles';

/// El bucket `mapas` simulado: el catálogo y los archivos, con soporte de `Range` (o sin él).
final class _Bucket {
  _Bucket() {
    archivos[_archivoMvd] = bytesDePrueba(5000);
    archivos[_archivoSalto1] = bytesDePrueba(4000);
    archivos[_archivoSalto2] = bytesDePrueba(3000, semilla: 9);
  }

  static const base = '/storage/v1/object/public/mapas/';

  final archivos = <String, List<int>>{};
  final pedidos = <http.BaseRequest>[];

  /// Un servidor que ignora `Range` y manda siempre el archivo entero (200).
  bool soportaRango = true;

  /// Cuántos bytes manda el próximo pedido de ese archivo antes de que se corte la conexión.
  final cortarEn = <String, int>{};

  /// Cuántos bytes manda el próximo pedido y cierra el cuerpo limpio, sin error (un archivo más
  /// corto de lo que dice el catálogo).
  final cerrarLimpioEn = <String, int>{};

  /// Cuántos bytes manda el próximo pedido y se queda callado con la conexión abierta (hasta que
  /// la app corta la bajada).
  final detenerEn = <String, int>{};

  /// Un archivo que se cambió en el bucket después de publicado el catálogo.
  final alterados = <String>{};

  /// El `tamano_bytes` que el catálogo declara en vez del real.
  final tamanoDeclarado = <String, int>{};

  /// Paquetes del catálogo que no cumplen el contrato (para ver que no tiran a los demás).
  final extras = <Map<String, dynamic>>[];

  static String _sha(List<int> bytes) => crypto.sha256.convert(bytes).toString();

  Map<String, dynamic> _parte(String archivo) => {
    'archivo': archivo,
    'tamano_bytes': tamanoDeclarado[archivo] ?? archivos[archivo]!.length,
    'sha256': _sha(archivos[archivo]!),
  };

  String get catalogo {
    final mvd = _parte(_archivoMvd);
    final salto1 = _parte(_archivoSalto1);
    final salto2 = _parte(_archivoSalto2);
    return jsonEncode({
      'version': 1,
      'paquetes': [
        ...extras,
        {
          'id': 'ciudad-montevideo',
          'nivel': 'ciudad',
          'ambito_id': 'c-mvd',
          'nombre': 'Montevideo',
          'version': mvd['sha256'],
          'partes': [mvd],
        },
        {
          'id': 'ciudad-salto',
          'nivel': 'ciudad',
          'ambito_id': 'c-salto',
          'nombre': 'Salto',
          'version': _sha(utf8.encode('${salto1['sha256']}\n${salto2['sha256']}')),
          'partes': [salto1, salto2],
        },
      ],
    });
  }

  Future<http.StreamedResponse> responder(http.BaseRequest pedido) async {
    pedidos.add(pedido);
    final ruta = pedido.url.path;
    if (!ruta.startsWith(base)) return _simple(404);
    final nombre = ruta.substring(base.length);
    if (nombre == 'catalogo.json') return _simple(200, utf8.encode(catalogo));
    var bytes = archivos[nombre];
    if (bytes == null) return _simple(404);
    if (alterados.contains(nombre)) bytes = [...bytes]..[bytes.length ~/ 2] ^= 0xFF;
    final rango = soportaRango
        ? RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(pedido.headers['range'] ?? '')
        : null;
    final desde = rango == null ? 0 : int.parse(rango.group(1)!);
    if (desde >= bytes.length) return _simple(416);
    final resto = bytes.sublist(desde);
    final headers = rango == null
        ? const <String, String>{}
        : {'content-range': 'bytes $desde-${bytes.length - 1}/${bytes.length}'};
    final status = rango == null ? 200 : 206;

    final parada = detenerEn.remove(nombre);
    if (parada != null) {
      final controlador = StreamController<List<int>>();
      for (final pedazo in _pedazos(resto.sublist(0, min(parada, resto.length)))) {
        controlador.add(pedazo);
      }
      return http.StreamedResponse(controlador.stream, status, headers: headers);
    }
    final corte = cortarEn.remove(nombre);
    final limpio = cerrarLimpioEn.remove(nombre);
    final hasta = min(corte ?? limpio ?? resto.length, resto.length);
    Stream<List<int>> cuerpo() async* {
      for (final pedazo in _pedazos(resto.sublist(0, hasta))) {
        yield pedazo;
      }
      if (corte != null) throw const SocketException('conexión cortada');
    }

    return http.StreamedResponse(cuerpo(), status, headers: headers);
  }

  http.StreamedResponse _simple(int status, [List<int> cuerpo = const []]) =>
      http.StreamedResponse(Stream.value(cuerpo), status);

  static Iterable<List<int>> _pedazos(List<int> bytes) sync* {
    for (var i = 0; i < bytes.length; i += 1000) {
      yield bytes.sublist(i, min(i + 1000, bytes.length));
    }
  }

  /// Los pedidos al archivo [nombre] (sin contar el catálogo).
  List<http.BaseRequest> deArchivo(String nombre) =>
      pedidos.where((r) => r.url.path.endsWith('/$nombre')).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel('test/almacenamiento_tiles_qa_191');
  late Directory temporal;
  late _Bucket bucket;
  late ConectividadFalsa conectividad;
  var bytesLibres = 1 << 40;
  final abiertas = <ComposicionTiles>[];

  Future<ComposicionTiles> abrir() async {
    final composicion = await ComposicionTiles.crear(
      directorioApp: temporal,
      conectividad: conectividad,
      supabaseUrl: 'https://x.supabase.co',
      cliente: MockClient.streaming((pedido, _) => bucket.responder(pedido)),
      canal: canal,
    );
    abiertas.add(composicion);
    await composicion.reconciliacion;
    return composicion;
  }

  Future<PaqueteTiles> delCatalogo(ComposicionTiles c, String id) async {
    final catalogo = (await c.repository.catalogo()).getOrElse(() => fail('catálogo'));
    return catalogo.singleWhere((paquete) => paquete.id == id);
  }

  /// Pide el paquete y espera a que termine el intento (completo, en pausa o fallido).
  Future<EstadoDescarga?> bajar(ComposicionTiles c, PaqueteTiles paquete) async {
    final resultado = await c.descargador.descargar(paquete);
    expect(resultado.isRight(), isTrue, reason: '$resultado');
    await c.descargador.esperar(paquete.id);
    return c.descargador.estadoDe(paquete.id);
  }

  /// Espera (en tiempo real: hay disco y red simulada de por medio) a que se cumpla [condicion].
  Future<void> hasta(bool Function() condicion, {String que = 'la condición'}) async {
    final limite = DateTime.now().add(const Duration(seconds: 10));
    while (!condicion()) {
      if (DateTime.now().isAfter(limite)) fail('No pasó: $que');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<List<PaqueteDescargado>> registrados(ComposicionTiles c) async =>
      (await c.repository.descargados()).getOrElse(() => fail('Left'));

  List<String> deDisco(ComposicionTiles c, String extension) => [
    for (final e in c.directorio.listSync())
      if (e.path.endsWith(extension)) e.path,
  ];

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('qa_hu_sync_010_');
    bucket = _Bucket();
    conectividad = ConectividadFalsa();
    bytesLibres = 1 << 40;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      (llamada) async => llamada.method == 'bytesLibres' ? bytesLibres : true,
    );
  });

  tearDown(() async {
    for (final composicion in abiertas) {
      await composicion.descargador.cerrar();
    }
    abiertas.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      null,
    );
    await temporal.delete(recursive: true);
  });

  group('descarga exitosa', () {
    test('dado Wi-Fi, cuando descargo Montevideo, el progreso sube de a poco hasta 100 %, se '
        'valida el checksum y el mapa offline lo tiene disponible', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      final estados = <EstadoDescarga>[];
      final escucha = c.descargador.cambios.listen(estados.add);

      final estado = await bajar(c, mvd);
      await Future<void>.delayed(Duration.zero);
      await escucha.cancel();

      expect(estado, isA<DescargaCompletada>());
      final progresos = estados.whereType<DescargaEnCurso>().map((e) => e.progreso).toList();
      expect(progresos.length, greaterThan(1), reason: 'hubo progreso, no un salto');
      expect(progresos, orderedEquals([...progresos]..sort()), reason: 'nunca retrocede');
      expect(progresos.last, 1.0);
      expect(estados.whereType<DescargaVerificando>(), hasLength(1));
      expect(estados.indexWhere((e) => e is DescargaVerificando), lessThan(estados.length - 1));
      final descargado = (estado! as DescargaCompletada).descargado;
      expect(await File(descargado.rutas.single).readAsBytes(), bucket.archivos[_archivoMvd]);
      expect(deDisco(c, '.part'), isEmpty);
      expect(await registrados(c), [descargado]);
      // El mapa offline lo elige para un lugar de Montevideo.
      expect(
        elegirPaqueteOffline(await registrados(c), const AmbitoTrabajo(ciudadId: 'c-mvd')),
        descargado,
      );
    });
  });

  group('sin espacio', () {
    test('dado un mapa de 87 MB y 50 MB libres, cuando intento descargar, la UI se bloquea con '
        '«Espacio insuficiente - faltan 37 MB» y no se pide ni un byte', () async {
      bucket.tamanoDeclarado[_archivoMvd] = 87000000;
      bytesLibres = 50000000;
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');

      final resultado = await c.descargador.descargar(mvd);

      final falla = resultado.fold((f) => f, (_) => null);
      expect(falla, const FailureEspacioInsuficiente(megabytesFaltantes: 37));
      expect(falla!.mensaje, startsWith('Espacio insuficiente - faltan 37 MB'));
      expect(bucket.deArchivo(_archivoMvd), isEmpty);
      expect(c.descargador.estadoDe(mvd.id), isNull, reason: 'no queda un estado trabado');
      expect(deDisco(c, '.part'), isEmpty);
      expect(await registrados(c), isEmpty);
    });

    test('dado que no había lugar, cuando libero espacio y vuelvo a tocar, descarga: el botón '
        'no quedó trabado', () async {
      bytesLibres = 1000;
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      expect((await c.descargador.descargar(mvd)).isLeft(), isTrue);

      bytesLibres = 1 << 40;
      final estado = await bajar(c, mvd);

      expect(estado, isA<DescargaCompletada>());
    });

    test('dado un .part ya bajado, el espacio que se pide es solo lo que falta', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      bucket.cortarEn[_archivoMvd] = 3000;
      expect(await bajar(c, mvd), isA<DescargaPausada>());

      bytesLibres = 2500;
      final estado = await bajar(c, mvd);

      expect(estado, isA<DescargaCompletada>());
    });
  });

  group('pausa y resume', () {
    for (final (perdida, motivo) in [
      (TipoConexion.datosMoviles, MotivoPausa.sinWifi),
      (TipoConexion.sinConexion, MotivoPausa.sinConexion),
    ]) {
      test('dado que bajo Montevideo y paso a ${perdida.name} a mitad, queda en pausa con el '
          '.part y, al volver el Wi-Fi, sigue desde el byte donde quedó (HTTP Range)', () async {
        final c = await abrir();
        final mvd = await delCatalogo(c, 'ciudad-montevideo');
        bucket.detenerEn[_archivoMvd] = 2000;
        expect((await c.descargador.descargar(mvd)).isRight(), isTrue);
        await hasta(() {
          final estado = c.descargador.estadoDe(mvd.id);
          return estado is DescargaEnCurso && estado.recibidos == 2000;
        }, que: 'llegaron los primeros 2000 bytes');

        conectividad.cambiarA(perdida);
        await c.descargador.esperar(mvd.id);

        final pausada = c.descargador.estadoDe(mvd.id)! as DescargaPausada;
        expect(pausada.motivo, motivo);
        expect(pausada.sigueSola, isTrue);
        expect(pausada.recibidos, 2000);
        expect(deDisco(c, '.part'), hasLength(1));
        expect(File(deDisco(c, '.part').single).lengthSync(), 2000);
        expect(await registrados(c), isEmpty, reason: 'un corte no deja un paquete a medias');
        expect(deDisco(c, '.pmtiles'), isEmpty);

        conectividad.cambiarA(TipoConexion.wifi);
        await hasta(
          () => c.descargador.estadoDe(mvd.id) is DescargaCompletada,
          que: 'la descarga sigue sola con el Wi-Fi',
        );

        expect(bucket.deArchivo(_archivoMvd).map((r) => r.headers['range']), [null, 'bytes=2000-']);
        final descargado = (c.descargador.estadoDe(mvd.id)! as DescargaCompletada).descargado;
        expect(await File(descargado.rutas.single).readAsBytes(), bucket.archivos[_archivoMvd]);
        expect(deDisco(c, '.part'), isEmpty);
      });
    }

    test('dado un servidor que ignora Range (200 en vez de 206), cuando sigue, reescribe el '
        '.part y el archivo queda entero y válido', () async {
      bucket.soportaRango = false;
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      bucket.cortarEn[_archivoMvd] = 2000;
      expect(await bajar(c, mvd), isA<DescargaPausada>());

      final estado = await bajar(c, mvd);

      expect(estado, isA<DescargaCompletada>());
      expect(bucket.deArchivo(_archivoMvd).last.headers['range'], 'bytes=2000-');
      final descargado = (estado! as DescargaCompletada).descargado;
      expect(await File(descargado.rutas.single).readAsBytes(), bucket.archivos[_archivoMvd]);
    });
  });

  group('solo Wi-Fi por defecto', () {
    test('dado datos móviles, cuando descargo sin autorizarlos, pide Wi-Fi y no baja nada; con '
        'la autorización sí baja', () async {
      conectividad.tipo = TipoConexion.datosMoviles;
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');

      final resultado = await c.descargador.descargar(mvd);

      expect(resultado.fold((f) => f, (_) => null), isA<FailureDescargaRequiereWifi>());
      expect(bucket.deArchivo(_archivoMvd), isEmpty);
      expect(deDisco(c, '.part'), isEmpty);

      final conPermiso = await c.descargador.descargar(mvd, permitirDatosMoviles: true);
      await c.descargador.esperar(mvd.id);

      expect(conPermiso.isRight(), isTrue);
      expect(c.descargador.estadoDe(mvd.id), isA<DescargaCompletada>());
    });

    test(
      'dado que descargo sin red, cuando toco, avisa que no hay conexión y no baja nada',
      () async {
        conectividad.tipo = TipoConexion.sinConexion;
        final c = await abrir();
        final mvd = await delCatalogo(c, 'ciudad-montevideo');

        final resultado = await c.descargador.descargar(mvd);

        expect(resultado.fold((f) => f, (_) => null), isA<FailureSinConexion>());
        expect(bucket.deArchivo(_archivoMvd), isEmpty);
      },
    );
  });

  group('eliminar de a uno', () {
    test('dado Montevideo y Salto descargados, cuando elimino Montevideo, Salto sigue ahí y '
        'Montevideo no vuelve al reabrir la app', () async {
      final primera = await abrir();
      final mvd = await delCatalogo(primera, 'ciudad-montevideo');
      final salto = await delCatalogo(primera, 'ciudad-salto');
      final deMvd = ((await bajar(primera, mvd))! as DescargaCompletada).descargado;
      final deSalto = ((await bajar(primera, salto))! as DescargaCompletada).descargado;

      final resultado = await primera.descargador.eliminar(mvd.id);

      expect(resultado.isRight(), isTrue);
      expect(File(deMvd.rutas.single).existsSync(), isFalse);
      expect(deSalto.rutas.every((r) => File(r).existsSync()), isTrue);
      expect(await registrados(primera), [deSalto]);

      await primera.descargador.cerrar();
      final segunda = await abrir();
      expect(await registrados(segunda), [deSalto]);
      expect(segunda.descargador.estadoDe(mvd.id), isNull);
    });

    test('dado que lo elimino y lo vuelvo a descargar, queda como nuevo', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      await bajar(c, mvd);
      await c.descargador.eliminar(mvd.id);

      final estado = await bajar(c, mvd);

      expect(estado, isA<DescargaCompletada>());
      expect(await registrados(c), hasLength(1));
    });
  });

  group('checksum inválido', () {
    test('dado un archivo alterado, cuando termina de bajar, se descarta (ni .part ni .pmtiles), '
        'no queda registrado y, arreglado el bucket, el reintento lo baja entero', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      bucket.alterados.add(_archivoMvd);

      final estado = await bajar(c, mvd);

      expect(estado, DescargaFallida(mvd.id, const FailurePaqueteTilesCorrupto()));
      expect(deDisco(c, '.part'), isEmpty);
      expect(deDisco(c, '.pmtiles'), isEmpty);
      expect(await registrados(c), isEmpty);

      bucket.alterados.clear();
      expect(await bajar(c, mvd), isA<DescargaCompletada>());
      // El reintento no reanuda sobre el archivo malo: pidió el archivo entero.
      expect(bucket.deArchivo(_archivoMvd).map((r) => r.headers['range']), [null, null]);
    });
  });

  group('fallos parciales', () {
    test('dado Montevideo que falla (404) y Salto que baja a la vez, Salto termina y el fallo de '
        'Montevideo no lo toca', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      final salto = await delCatalogo(c, 'ciudad-salto');
      bucket.archivos.remove(_archivoMvd);

      final pedidos = await Future.wait([
        c.descargador.descargar(mvd),
        c.descargador.descargar(salto),
      ]);
      await Future.wait([c.descargador.esperar(mvd.id), c.descargador.esperar(salto.id)]);

      expect(pedidos.every((r) => r.isRight()), isTrue);
      expect(
        c.descargador.estadoDe(mvd.id),
        DescargaFallida(mvd.id, const FailureServidor(status: 404)),
      );
      expect(c.descargador.estadoDe(salto.id), isA<DescargaCompletada>());
      expect((await registrados(c)).map((d) => d.paquete.id), ['ciudad-salto']);
    });

    test('dado que falla Montevideo, cuando vuelvo a tocar «Descargar», no queda trabado: baja '
        'con la versión que ya está bien', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      final entero = bucket.archivos.remove(_archivoMvd)!;
      expect(await bajar(c, mvd), isA<DescargaFallida>());

      bucket.archivos[_archivoMvd] = entero;
      final estado = await bajar(c, mvd);

      expect(estado, isA<DescargaCompletada>());
    });

    test('dado dos toques seguidos en «Descargar», pide el archivo una sola vez', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');

      final pedidos = await Future.wait([
        c.descargador.descargar(mvd),
        c.descargador.descargar(mvd),
      ]);
      await c.descargador.esperar(mvd.id);

      expect(pedidos.every((r) => r.isRight()), isTrue);
      expect(bucket.deArchivo(_archivoMvd), hasLength(1));
      expect(c.descargador.estadoDe(mvd.id), isA<DescargaCompletada>());
      expect(await registrados(c), hasLength(1));
    });

    test('dado que se corta la red dos veces seguidas en la misma parte, cada reanudación sigue '
        'desde donde quedó y el archivo final es el del catálogo', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      bucket.cortarEn[_archivoMvd] = 1500;
      expect(await bajar(c, mvd), isA<DescargaPausada>());
      bucket.cortarEn[_archivoMvd] = 1000;
      final segundo = await bajar(c, mvd);
      expect((segundo! as DescargaPausada).recibidos, 2500);

      final estado = await bajar(c, mvd);

      expect(estado, isA<DescargaCompletada>());
      expect(bucket.deArchivo(_archivoMvd).map((r) => r.headers['range']), [
        null,
        'bytes=1500-',
        'bytes=2500-',
      ]);
      final descargado = (estado! as DescargaCompletada).descargado;
      expect(await File(descargado.rutas.single).readAsBytes(), bucket.archivos[_archivoMvd]);
    });

    test('dado Salto en dos partes con la segunda cortada, la primera queda validada y al seguir '
        'no se vuelve a bajar', () async {
      final c = await abrir();
      final salto = await delCatalogo(c, 'ciudad-salto');
      bucket.cortarEn[_archivoSalto2] = 500;
      expect(await bajar(c, salto), isA<DescargaPausada>());

      final estado = await bajar(c, salto);

      expect(estado, isA<DescargaCompletada>());
      expect(bucket.deArchivo(_archivoSalto1), hasLength(1));
      expect(bucket.deArchivo(_archivoSalto2).map((r) => r.headers['range']), [null, 'bytes=500-']);
    });
  });

  group('el archivo no es lo que dice el catálogo (consistencia del payload)', () {
    test('dado un archivo más corto que el tamaño del catálogo y la conexión cerrada sin error, '
        'queda en pausa sin registrarse como válido', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      bucket.cerrarLimpioEn[_archivoMvd] = 3500;

      final estado = await bajar(c, mvd);

      expect(estado, isA<DescargaPausada>());
      expect((estado! as DescargaPausada).recibidos, 3500);
      expect(await registrados(c), isEmpty);
      expect(deDisco(c, '.pmtiles'), isEmpty);

      // Y se completa pidiendo solo el resto.
      expect(await bajar(c, mvd), isA<DescargaCompletada>());
      expect(bucket.deArchivo(_archivoMvd).last.headers['range'], 'bytes=3500-');
    });

    test('dado un archivo más grande que el tamaño del catálogo, se corta, se descarta y falla '
        'como paquete dañado', () async {
      bucket.tamanoDeclarado[_archivoMvd] = 4000;
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');

      final estado = await bajar(c, mvd);

      expect(estado, DescargaFallida(mvd.id, const FailurePaqueteTilesCorrupto()));
      expect(deDisco(c, '.part'), isEmpty);
      expect(deDisco(c, '.pmtiles'), isEmpty);
      expect(await registrados(c), isEmpty);
    });

    test('dado un paquete del catálogo con un checksum que no es SHA-256, se descarta solo y los '
        'demás se pueden descargar', () async {
      bucket.extras.add({
        'id': 'ciudad-rota',
        'nivel': 'ciudad',
        'ambito_id': 'c-rota',
        'version': 'v1',
        'partes': [
          {'archivo': _archivoMvd, 'tamano_bytes': 5000, 'sha256': 'no-es-un-hash'},
        ],
      });
      final c = await abrir();

      final catalogo = (await c.repository.catalogo()).getOrElse(() => fail('catálogo'));

      expect(catalogo.map((p) => p.id), ['ciudad-montevideo', 'ciudad-salto']);
      expect(await bajar(c, catalogo.first), isA<DescargaCompletada>());
    });

    test('dado un archivo reemplazado en el bucket bajo el mismo nombre mientras había un .part, '
        'los bytes de dos versiones no pasan por válidos', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      final viejo = List<int>.of(bucket.archivos[_archivoMvd]!);
      bucket.cortarEn[_archivoMvd] = 2000;
      expect(await bajar(c, mvd), isA<DescargaPausada>());

      // Se publica otro contenido bajo el mismo nombre: el `.part` no es de ese archivo.
      bucket.archivos[_archivoMvd] = bytesDePrueba(5000, semilla: 77);
      final estado = await bajar(c, mvd);

      // El checksum es el del catálogo que se pidió: la mezcla no valida y nunca queda registrada.
      expect(estado, isA<DescargaFallida>());
      expect((estado! as DescargaFallida).failure, isA<FailurePaqueteTilesCorrupto>());
      expect(await registrados(c), isEmpty);
      expect(deDisco(c, '.part'), isEmpty);
      expect(viejo, isNot(bucket.archivos[_archivoMvd]));
    });
  });
}

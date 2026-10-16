// Test de integración de los adaptadores reales de los mapas (HU-SYNC-010, #189): HTTP, archivos
// del disco, SHA-256, manifiesto y canal nativo, contra un bucket simulado. Lo único falso es el
// servidor (`MockClient`), el lado nativo del canal y la conectividad.
//
// No prueba contra el bucket real: el mapa se publica el jueves 08/10.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tiles/data/composicion_tiles.dart';
import 'package:colportores_mobile/features/tiles/data/datasources/descargas_pendientes_json.dart';
import 'package:colportores_mobile/features/tiles/data/models/descarga_pendiente_model.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/descarga_pendiente.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/estado_descarga.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../../../../helpers/tiles_falsos.dart';

/// El bucket `mapas`: el catálogo y los archivos, con soporte de `Range`.
final class _Bucket {
  _Bucket() {
    archivos['ciudad-mvd-3f9c1a2b7d44.pmtiles'] = bytesDePrueba(5000);
    archivos['ciudad-salto-9a1b2c3d4e5f-p1.pmtiles'] = bytesDePrueba(4000);
    archivos['ciudad-salto-0f1e2d3c4b5a-p2.pmtiles'] = bytesDePrueba(3000, semilla: 9);
  }

  static const base = '/storage/v1/object/public/mapas/';

  final archivos = <String, List<int>>{};
  final pedidos = <http.BaseRequest>[];

  /// El archivo de Montevideo que nombra el catálogo (cambia cuando se publica otra versión).
  String archivoMvd = 'ciudad-mvd-3f9c1a2b7d44.pmtiles';

  /// Cuántos bytes manda el próximo pedido de ese archivo antes de que se corte la conexión.
  final cortarEn = <String, int>{};

  /// Un archivo que se cambió en el bucket después de publicado el catálogo.
  final alterados = <String>{};

  static String _sha(List<int> bytes) => crypto.sha256.convert(bytes).toString();

  Map<String, dynamic> _parte(String archivo) => {
    'archivo': archivo,
    'tamano_bytes': archivos[archivo]!.length,
    'sha256': _sha(archivos[archivo]!),
  };

  String get catalogo {
    final mvd = _parte(archivoMvd);
    final salto1 = _parte('ciudad-salto-9a1b2c3d4e5f-p1.pmtiles');
    final salto2 = _parte('ciudad-salto-0f1e2d3c4b5a-p2.pmtiles');
    return jsonEncode({
      'version': 1,
      'paquetes': [
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
    // `bytes=<desde>-` (la descarga) o `bytes=<desde>-<hasta>` (la prueba del mapa, `bytes=0-0`).
    final rango = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(pedido.headers['range'] ?? '');
    final desde = rango == null ? 0 : int.parse(rango.group(1)!);
    if (desde >= bytes.length) return _simple(416);
    final pedidoHasta = rango?.group(2) ?? '';
    final hasta = pedidoHasta.isEmpty
        ? bytes.length - 1
        : min(int.parse(pedidoHasta), bytes.length - 1);
    final resto = bytes.sublist(desde, hasta + 1);
    final corte = cortarEn.remove(nombre);
    final cuerpo = _pedazos(resto, corte);
    return http.StreamedResponse(
      cuerpo,
      rango == null ? 200 : 206,
      headers: rango == null ? const {} : {'content-range': 'bytes $desde-$hasta/${bytes.length}'},
    );
  }

  http.StreamedResponse _simple(int status, [List<int> cuerpo = const []]) =>
      http.StreamedResponse(Stream.value(cuerpo), status);

  Stream<List<int>> _pedazos(List<int> resto, int? corte) async* {
    final hasta = corte ?? resto.length;
    for (var i = 0; i < hasta; i += 1000) {
      yield resto.sublist(i, i + 1000 > hasta ? hasta : i + 1000);
    }
    if (corte != null) throw const SocketException('conexión cortada');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel('test/almacenamiento_tiles');
  late Directory temporal;
  late _Bucket bucket;
  late ConectividadFalsa conectividad;
  late List<MethodCall> llamadasNativas;
  final abiertas = <ComposicionTiles>[];

  Future<ComposicionTiles> abrir({String supabaseUrl = 'https://x.supabase.co'}) async {
    final composicion = await ComposicionTiles.crear(
      directorioApp: temporal,
      conectividad: conectividad,
      supabaseUrl: supabaseUrl,
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

  Future<EstadoDescarga?> bajar(ComposicionTiles c, PaqueteTiles paquete) async {
    final resultado = await c.descargador.descargar(paquete);
    expect(resultado.isRight(), isTrue, reason: '$resultado');
    await c.descargador.esperar(paquete.id);
    return c.descargador.estadoDe(paquete.id);
  }

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('composicion_tiles_');
    bucket = _Bucket();
    conectividad = ConectividadFalsa();
    llamadasNativas = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      (llamada) async {
        llamadasNativas.add(llamada);
        return llamada.method == 'bytesLibres' ? 1 << 40 : true;
      },
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

  test('crea la carpeta de los paquetes y la saca de la copia de seguridad', () async {
    final c = await abrir();

    expect(c.directorio.path, p.join(temporal.path, 'tiles'));
    expect(c.directorio.existsSync(), isTrue);
    final exclusion = llamadasNativas.singleWhere((l) => l.method == 'excluirDeBackup');
    expect(exclusion.arguments, {'ruta': c.directorio.path});
  });

  test('el catálogo sale del bucket público «mapas» del proyecto', () async {
    final c = await abrir();

    final catalogo = (await c.repository.catalogo()).getOrElse(() => fail('catálogo'));

    expect(catalogo.map((paquete) => paquete.id), ['ciudad-montevideo', 'ciudad-salto']);
    expect(
      bucket.pedidos.single.url.toString(),
      'https://x.supabase.co${_Bucket.base}catalogo.json',
    );
  });

  test('sin Supabase configurado (tests, demo) el catálogo está vacío y no hay red', () async {
    final c = await abrir(supabaseUrl: '');

    expect((await c.repository.catalogo()).getOrElse(() => fail('catálogo')), isEmpty);
    expect(bucket.pedidos, isEmpty);
  });

  group('la prueba del archivo del mapa en línea (#299)', () {
    test('pide 1 byte con Range al archivo del bucket y no baja más', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      bucket.pedidos.clear();

      await c.sonda.probar(mvd.partes.single.origen);

      final pedido = bucket.pedidos.single;
      expect(pedido.url, mvd.partes.single.origen);
      expect(pedido.headers['range'], 'bytes=0-0');
    });

    test('un archivo que ya no está en el bucket es un ErrorServidorTiles 404', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      bucket.archivos.remove('ciudad-mvd-3f9c1a2b7d44.pmtiles');

      await expectLater(
        c.sonda.probar(mvd.partes.single.origen),
        throwsA(isA<ErrorServidorTiles>().having((e) => e.status, 'status', 404)),
      );
    });

    test('las dos partes de una ciudad grande se prueban por separado', () async {
      final c = await abrir();
      final salto = await delCatalogo(c, 'ciudad-salto');
      bucket.archivos.remove('ciudad-salto-0f1e2d3c4b5a-p2.pmtiles');

      await c.sonda.probar(salto.partes[0].origen);
      await expectLater(c.sonda.probar(salto.partes[1].origen), throwsA(isA<ErrorServidorTiles>()));
    });
  });

  group('una ciudad en un solo archivo', () {
    test('se baja, se valida, se renombra y queda registrada con su archivo', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');

      final estado = await bajar(c, mvd);

      expect(estado, isA<DescargaCompletada>());
      final descargado = (estado! as DescargaCompletada).descargado;
      final archivo = File(descargado.rutas.single);
      expect(p.dirname(archivo.path), c.directorio.path);
      expect(archivo.path, endsWith('ciudad-montevideo-p1-${mvd.partes.single.huella}.pmtiles'));
      expect(await archivo.readAsBytes(), bucket.archivos['ciudad-mvd-3f9c1a2b7d44.pmtiles']);
      // Lo anotado se olvida sin esperar: se lee antes de listar para no ver el `.tmp` de esa escritura.
      expect((await c.repository.descargasPendientes()).getOrElse(() => fail('Left')), isEmpty);
      expect(c.directorio.listSync().map((e) => p.basename(e.path)).toSet(), {
        p.basename(archivo.path),
        'registro.json',
        'descargas_pendientes.json',
      });
      expect((await c.repository.descargados()).getOrElse(() => fail('Left')), [descargado]);
    });

    test('el registro sobrevive a cerrar la app: la sesión siguiente ya lo tiene', () async {
      final primera = await abrir();
      final mvd = await delCatalogo(primera, 'ciudad-montevideo');
      final descargado = ((await bajar(primera, mvd))! as DescargaCompletada).descargado;
      await primera.descargador.cerrar();

      final segunda = await abrir();

      expect((await segunda.repository.descargados()).getOrElse(() => fail('Left')), [descargado]);
      expect(
        elegirPaqueteOffline([descargado], const AmbitoTrabajo(ciudadId: 'c-mvd')),
        descargado,
      );
    });

    test('un archivo que no es el del catálogo (otro contenido) no queda como válido', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      bucket.alterados.add('ciudad-mvd-3f9c1a2b7d44.pmtiles');

      final estado = await bajar(c, mvd);

      expect(estado, isA<DescargaFallida>());
      expect((estado! as DescargaFallida).failure, isA<FailurePaqueteTilesCorrupto>());
      expect((await c.repository.descargados()).getOrElse(() => fail('Left')), isEmpty);
      expect(c.directorio.listSync().where((e) => e.path.endsWith('.pmtiles')), isEmpty);
      expect(c.directorio.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
    });

    test('un archivo que ya no está en el bucket falla con el 404, sin dejar nada', () async {
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');
      bucket.archivos.remove('ciudad-mvd-3f9c1a2b7d44.pmtiles');

      final estado = await bajar(c, mvd);

      expect(estado, DescargaFallida(mvd.id, const FailureServidor(status: 404)));
    });

    test('con el teléfono sin lugar, no pide ni un byte del archivo', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        canal,
        (llamada) async => llamada.method == 'bytesLibres' ? 1000 : true,
      );
      final c = await abrir();
      final mvd = await delCatalogo(c, 'ciudad-montevideo');

      final resultado = await c.descargador.descargar(mvd);

      expect(
        resultado.fold((f) => f, (_) => null),
        const FailureEspacioInsuficiente(megabytesFaltantes: 1),
      );
      expect(bucket.pedidos.where((r) => r.url.path.endsWith('.pmtiles')), isEmpty);
    });
  });

  group('una ciudad en dos archivos', () {
    test('baja las dos partes, las valida y registra el paquete con las dos rutas', () async {
      final c = await abrir();
      final salto = await delCatalogo(c, 'ciudad-salto');

      final estado = await bajar(c, salto);

      expect(estado, isA<DescargaCompletada>());
      final descargado = (estado! as DescargaCompletada).descargado;
      expect(descargado.rutas, hasLength(2));
      expect(
        await File(descargado.rutas[0]).readAsBytes(),
        bucket.archivos['ciudad-salto-9a1b2c3d4e5f-p1.pmtiles'],
      );
      expect(
        await File(descargado.rutas[1]).readAsBytes(),
        bucket.archivos['ciudad-salto-0f1e2d3c4b5a-p2.pmtiles'],
      );
      expect(descargado.rutas[0], endsWith('ciudad-salto-p1-${salto.partes[0].huella}.pmtiles'));
      expect(descargado.rutas[1], endsWith('ciudad-salto-p2-${salto.partes[1].huella}.pmtiles'));
    });

    test('una conexión que se corta a mitad de la segunda parte sigue desde donde quedó', () async {
      final c = await abrir();
      final salto = await delCatalogo(c, 'ciudad-salto');
      bucket.cortarEn['ciudad-salto-0f1e2d3c4b5a-p2.pmtiles'] = 1500;

      final cortado = await bajar(c, salto);

      expect(cortado, isA<DescargaPausada>());
      final pausada = cortado! as DescargaPausada;
      expect(pausada.motivo, MotivoPausa.sinConexion);
      expect(pausada.recibidos, 4000 + 1500);
      expect((await c.repository.descargados()).getOrElse(() => fail('Left')), isEmpty);

      final completo = await bajar(c, salto);

      expect(completo, isA<DescargaCompletada>());
      final segunda = bucket.pedidos.where((r) => r.url.path.endsWith('-p2.pmtiles')).toList();
      expect(segunda.map((r) => r.headers['range']), [null, 'bytes=1500-']);
      final rutas = (completo! as DescargaCompletada).descargado.rutas;
      expect(
        await File(rutas[1]).readAsBytes(),
        bucket.archivos['ciudad-salto-0f1e2d3c4b5a-p2.pmtiles'],
      );
    });

    test('con una parte alterada no se registra el paquete ni se deja la otra parte', () async {
      final c = await abrir();
      final salto = await delCatalogo(c, 'ciudad-salto');
      bucket.alterados.add('ciudad-salto-0f1e2d3c4b5a-p2.pmtiles');

      final estado = await bajar(c, salto);

      expect(estado, isA<DescargaFallida>());
      expect((await c.repository.descargados()).getOrElse(() => fail('Left')), isEmpty);
      expect(c.directorio.listSync().where((e) => e.path.endsWith('.pmtiles')), isEmpty);
    });
  });

  group('al arrancar la app (reconciliar)', () {
    test('un archivo bajado que se corrompió en el disco se descarta y se borra', () async {
      final primera = await abrir();
      final mvd = await delCatalogo(primera, 'ciudad-montevideo');
      final descargado = ((await bajar(primera, mvd))! as DescargaCompletada).descargado;
      await primera.descargador.cerrar();
      final archivo = File(descargado.rutas.single);
      final bytes = await archivo.readAsBytes();
      bytes[100] ^= 0xFF;
      await archivo.writeAsBytes(bytes);
      // Un archivo que se dañó en el disco no es de una descarga en curso: tiene su fecha vieja,
      // pasada la gracia con la que `reconciliar` no toca lo recién renombrado.
      archivo.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));

      final segunda = await abrir();

      expect((await segunda.repository.descargados()).getOrElse(() => fail('Left')), isEmpty);
      expect(archivo.existsSync(), isFalse);
    });

    test('un archivo que el sistema truncó se descarta', () async {
      final primera = await abrir();
      final mvd = await delCatalogo(primera, 'ciudad-montevideo');
      final descargado = ((await bajar(primera, mvd))! as DescargaCompletada).descargado;
      await primera.descargador.cerrar();
      await File(descargado.rutas.single).writeAsBytes([1, 2, 3]);

      final segunda = await abrir();

      expect((await segunda.repository.descargados()).getOrElse(() => fail('Left')), isEmpty);
    });

    test('un .part abandonado hace más de 7 días se borra; uno reciente se conserva', () async {
      await Directory(p.join(temporal.path, 'tiles')).create(recursive: true);
      final viejo = File(p.join(temporal.path, 'tiles', 'viejo-p1-aaaaaaaaaaaa.pmtiles.part'))
        ..writeAsBytesSync([1]);
      viejo.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));
      final reciente = File(p.join(temporal.path, 'tiles', 'nuevo-p1-bbbbbbbbbbbb.pmtiles.part'))
        ..writeAsBytesSync([2]);

      await abrir();

      expect(viejo.existsSync(), isFalse);
      expect(reciente.existsSync(), isTrue);
    });
  });

  group('la descarga sigue después de cerrar la app (#300)', () {
    const archivoMvd = 'ciudad-mvd-3f9c1a2b7d44.pmtiles';

    File manifiesto(ComposicionTiles c) =>
        File(p.join(c.directorio.path, DescargasPendientesJson.nombreArchivo));

    /// Espera a que lo anotado haya llegado al disco (las lecturas hacen cola con las escrituras).
    Future<List<DescargaPendiente>> anotadas(ComposicionTiles c) async =>
        (await c.repository.descargasPendientes()).getOrElse(() => fail('Left'));

    /// Los `Range` que pidió la app para bajar [archivo] (no la prueba del mapa ni el catálogo).
    List<String?> rangos(String archivo) => [
      for (final pedido in bucket.pedidos)
        if (pedido.url.path.endsWith(archivo)) pedido.headers['range'],
    ];

    test('dado que se cerró con la descarga cortada a medias, al abrirla sigue desde el byte que '
        'quedó, sobre el mismo archivo', () async {
      final primera = await abrir();
      final mvd = await delCatalogo(primera, 'ciudad-montevideo');
      bucket.cortarEn[archivoMvd] = 2000;
      await primera.descargador.descargar(mvd, permitirDatosMoviles: true, esperarConexion: true);
      await primera.descargador.esperar(mvd.id);
      expect(primera.descargador.estadoDe(mvd.id), isA<DescargaPausada>());
      expect((await anotadas(primera)).single.paquete, mvd);
      expect(manifiesto(primera).existsSync(), isTrue);
      await primera.descargador.cerrar();
      bucket.pedidos.clear();

      final segunda = await abrir();
      await segunda.descargador.esperar(mvd.id);

      expect(segunda.descargador.estadoDe(mvd.id), isA<DescargaCompletada>());
      expect(rangos(archivoMvd), ['bytes=2000-']);
      final descargados = (await segunda.repository.descargados()).getOrElse(() => fail('Left'));
      expect(descargados.single.paquete, mvd);
      expect(
        await File(descargados.single.rutas.single).readAsBytes(),
        bucket.archivos[archivoMvd],
      );
      expect(await anotadas(segunda), isEmpty);
    });

    test('dado que el pedido quedó en cola sin señal y nunca arrancó, al abrir la app con señal '
        'arranca solo', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final primera = await abrir();
      final mvd = await delCatalogo(primera, 'ciudad-montevideo');
      await primera.descargador.descargar(mvd, permitirDatosMoviles: true, esperarConexion: true);
      expect((await anotadas(primera)).single.paquete, mvd);
      expect(rangos(archivoMvd), isEmpty);
      await primera.descargador.cerrar();
      conectividad.tipo = TipoConexion.wifi;

      final segunda = await abrir();
      await segunda.descargador.esperar(mvd.id);

      expect(segunda.descargador.estadoDe(mvd.id), isA<DescargaCompletada>());
      expect(rangos(archivoMvd), [null]);
      expect(await anotadas(segunda), isEmpty);
    });

    test('dado que se abre otra vez sin señal, sigue en cola y arranca con la primera conexión que '
        'vuelva', () async {
      conectividad.tipo = TipoConexion.sinConexion;
      final primera = await abrir();
      final mvd = await delCatalogo(primera, 'ciudad-montevideo');
      await primera.descargador.descargar(mvd, permitirDatosMoviles: true, esperarConexion: true);
      await anotadas(primera);
      await primera.descargador.cerrar();

      final segunda = await abrir();

      expect(segunda.descargador.estadoDe(mvd.id), isA<DescargaPausada>());
      expect(
        segunda.descargador.paqueteEnMarchaQueCubre(const AmbitoTrabajo(ciudadId: 'c-mvd')),
        mvd,
      );
      expect(rangos(archivoMvd), isEmpty);
      conectividad.cambiarA(TipoConexion.datosMoviles);
      await segunda.descargador.esperar(mvd.id);

      expect(segunda.descargador.estadoDe(mvd.id), isA<DescargaCompletada>());
    });

    test('dado que el catálogo ya trae otra versión, termina el archivo que empezó y la versión '
        'nueva se baja después', () async {
      final primera = await abrir();
      final viejo = await delCatalogo(primera, 'ciudad-montevideo');
      bucket.cortarEn[archivoMvd] = 2000;
      await primera.descargador.descargar(viejo, esperarConexion: true);
      await primera.descargador.esperar(viejo.id);
      await anotadas(primera);
      await primera.descargador.cerrar();
      // Se publica otra versión; el archivo anterior sigue 7 días en el bucket.
      const archivoNuevo = 'ciudad-mvd-aaaaaaaaaaaa.pmtiles';
      bucket
        ..archivos[archivoNuevo] = bytesDePrueba(6000, semilla: 9)
        ..archivoMvd = archivoNuevo
        ..pedidos.clear();

      final segunda = await abrir();
      final nuevo = await delCatalogo(segunda, 'ciudad-montevideo');
      await segunda.descargador.esperar(viejo.id);

      expect(nuevo.version, isNot(viejo.version));
      expect(segunda.descargador.estadoDe(viejo.id), isA<DescargaCompletada>());
      expect(rangos(archivoMvd), ['bytes=2000-']);
      expect(rangos(archivoNuevo), isEmpty);
      var descargados = (await segunda.repository.descargados()).getOrElse(() => fail('Left'));
      expect(descargados.single.paquete, viejo);

      final estado = await bajar(segunda, nuevo);

      expect(estado, isA<DescargaCompletada>());
      descargados = (await segunda.repository.descargados()).getOrElse(() => fail('Left'));
      expect(descargados.single.paquete, nuevo);
    });

    test(
      'dado que la descarga tiene más de 7 días, al abrir la app se olvida sin bajar nada',
      () async {
        final primera = await abrir();
        final mvd = await delCatalogo(primera, 'ciudad-montevideo');
        await primera.descargador.cerrar();
        final vieja = DescargaPendiente(
          paquete: mvd,
          anotadaEn: DateTime.now().subtract(const Duration(days: 8)),
        );
        manifiesto(primera).writeAsStringSync(
          jsonEncode({
            'version': 1,
            'descargas': [DescargaPendienteModel.aJson(vieja)],
          }),
        );
        bucket.pedidos.clear();

        final segunda = await abrir();

        expect(await anotadas(segunda), isEmpty);
        expect(segunda.descargador.estadoDe(mvd.id), isNull);
        expect(rangos(archivoMvd), isEmpty);
      },
    );

    test('dado una descarga anotada de un paquete que ya está descargado con esa versión, al abrir '
        'la app no se baja de nuevo: primero se reconcilia y recién después se retoma', () async {
      final primera = await abrir();
      final mvd = await delCatalogo(primera, 'ciudad-montevideo');
      expect(await bajar(primera, mvd), isA<DescargaCompletada>());
      await anotadas(primera); // que la escritura de «olvidar» salga antes de pisar el manifiesto
      manifiesto(primera).writeAsStringSync(
        jsonEncode({
          'version': 1,
          'descargas': [
            DescargaPendienteModel.aJson(
              DescargaPendiente(
                paquete: mvd,
                anotadaEn: DateTime.now(),
                permitirDatosMoviles: true,
              ),
            ),
          ],
        }),
      );
      await primera.descargador.cerrar();
      bucket.pedidos.clear();

      final segunda = await abrir();
      await segunda.descargador.esperar(mvd.id);

      expect(rangos(archivoMvd), isEmpty);
      expect(await anotadas(segunda), isEmpty);
    });

    test('dado un manifiesto de descargas roto, la app abre igual y no retoma nada', () async {
      final primera = await abrir();
      await primera.descargador.cerrar();
      manifiesto(primera).writeAsStringSync('{"version":1,"desc');
      bucket.pedidos.clear();

      final segunda = await abrir();

      expect(await anotadas(segunda), isEmpty);
      expect(bucket.pedidos, isEmpty);
    });

    test('dado que la elimino antes de cerrar la app, al abrirla no se retoma', () async {
      final primera = await abrir();
      final mvd = await delCatalogo(primera, 'ciudad-montevideo');
      bucket.cortarEn[archivoMvd] = 2000;
      await primera.descargador.descargar(mvd, esperarConexion: true);
      await primera.descargador.esperar(mvd.id);
      await primera.descargador.eliminar(mvd.id);
      await primera.descargador.cerrar();
      bucket.pedidos.clear();

      final segunda = await abrir();

      expect(await anotadas(segunda), isEmpty);
      expect(segunda.descargador.estadoDe(mvd.id), isNull);
      expect(rangos(archivoMvd), isEmpty);
      expect(segunda.directorio.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
    });
  });

  group('eliminar', () {
    test('saca el paquete del registro y borra sus archivos, de cualquier versión', () async {
      final c = await abrir();
      final salto = await delCatalogo(c, 'ciudad-salto');
      final rutas = ((await bajar(c, salto))! as DescargaCompletada).descargado.rutas;
      final deOtraVersion = File(p.join(c.directorio.path, 'ciudad-salto-p1-cccccccccccc.pmtiles'))
        ..writeAsBytesSync([9]);

      final resultado = await c.descargador.eliminar('ciudad-salto');

      expect(resultado.isRight(), isTrue);
      expect(rutas.any((r) => File(r).existsSync()), isFalse);
      expect(deOtraVersion.existsSync(), isFalse);
      expect((await c.repository.descargados()).getOrElse(() => fail('Left')), isEmpty);
    });
  });
}

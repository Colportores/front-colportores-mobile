// Los glyphs y sprites del mapa se copian al almacenamiento interno para que MapLibre los lea con
// `file://` (#286). Usa los assets de verdad: también prueba que `pubspec.yaml` los declara.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/features/mapa/data/services/preparador_recursos_mapa.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Un bundle que sirve los assets de verdad pero se cae en cada glyph, como un disco que falla a
/// mitad de la copia.
class _BundleQueFalla extends AssetBundle {
  var fallas = 0;

  @override
  Future<ByteData> load(String key) {
    if (key.endsWith('.pbf')) {
      fallas++;
      throw FlutterError('no se pudo leer $key');
    }
    return rootBundle.load(key);
  }

  @override
  Future<T> loadStructuredBinaryData<T>(String key, FutureOr<T> Function(ByteData data) parser) =>
      rootBundle.loadStructuredBinaryData(key, parser);
}

List<String> _archivos(Directory raiz) => [
  for (final e in raiz.listSync(recursive: true))
    if (e is File) p.relative(e.path, from: raiz.path).replaceAll(r'\', '/'),
]..sort();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('mapa286_');
  });

  tearDown(() async {
    if (base.existsSync()) await base.delete(recursive: true);
  });

  PreparadorRecursosMapa preparador({String version = 'v1', AssetBundle? bundle}) =>
      PreparadorRecursosMapa(directorioBase: () async => base, bundle: bundle, version: version);

  test('copia los glyphs y los sprites a <soporte>/mapa/<versión>/ y marca que terminó', () async {
    final ruta = await preparador().preparar();

    expect(ruta, p.join(base.path, 'mapa', 'v1'));
    final archivos = _archivos(Directory(ruta));
    expect(archivos, contains('.listo'));
    for (final fuente in ['NotoSans-Regular', 'NotoSans-Medium', 'NotoSans-Italic']) {
      for (final rango in ['0-255', '256-511', '8192-8447']) {
        expect(archivos, contains('glyphs/$fuente/$rango.pbf'));
      }
    }
    expect(
      archivos,
      containsAll(['sprites/grayscale.json', 'sprites/grayscale.png', 'sprites/grayscale@2x.png']),
    );
    // El estilo y el aviso de licencias no hacen falta en disco: el estilo se lee del bundle.
    expect(archivos.where((a) => !a.startsWith('glyphs/') && !a.startsWith('sprites/')), [
      '.listo',
    ]);
    expect(
      File(p.join(ruta, 'glyphs', 'NotoSans-Regular', '0-255.pbf')).lengthSync(),
      greaterThan(0),
    );
  });

  test('las siguientes veces no copia de nuevo', () async {
    final ruta = await preparador().preparar();
    final borrado = File(p.join(ruta, 'sprites', 'grayscale.json'))..deleteSync();

    final otra = await preparador().preparar();

    expect(otra, ruta);
    expect(borrado.existsSync(), isFalse, reason: 'la marca de «listo» corta la copia');
  });

  test('varias llamadas a la vez comparten una sola copia', () async {
    final preparador0 = preparador();

    final a = preparador0.preparar();
    final b = preparador0.preparar();

    expect(identical(a, b), isTrue);
    expect(await a, await b);
  });

  test('una versión nueva borra las anteriores', () async {
    await preparador(version: 'v1').preparar();

    final ruta = await preparador(version: 'v2').preparar();

    expect(Directory(p.join(base.path, 'mapa', 'v1')).existsSync(), isFalse);
    expect(File(p.join(ruta, '.listo')).existsSync(), isTrue);
  });

  test('una copia que quedó a medias de una corrida anterior se rehace', () async {
    final raiz = p.join(base.path, 'mapa');
    // Quedó un temporal con basura y un destino sin la marca de «listo».
    File(p.join(raiz, 'v1.tmp', 'sobra.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    File(p.join(raiz, 'v1', 'glyphs', 'a-medias.pbf'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');

    final ruta = await preparador().preparar();

    final archivos = _archivos(Directory(ruta));
    expect(archivos, contains('.listo'));
    expect(archivos, isNot(contains('glyphs/a-medias.pbf')));
    expect(Directory(p.join(raiz, 'v1.tmp')).existsSync(), isFalse);
  });

  test('si la copia falla, no deja una versión «lista» y la próxima vez se reintenta', () async {
    final bundle = _BundleQueFalla();
    final fallido = preparador(bundle: bundle);

    await expectLater(fallido.preparar(), throwsA(isA<FlutterError>()));

    expect(bundle.fallas, 1);
    expect(File(p.join(base.path, 'mapa', 'v1', '.listo')).existsSync(), isFalse);

    // La falla no deja una copia en curso colgada: el mismo preparador reintenta de verdad.
    await expectLater(fallido.preparar(), throwsA(isA<FlutterError>()));
    expect(bundle.fallas, 2);

    // Y con un disco que anda, la copia sale.
    final ruta = await preparador().preparar();
    expect(File(p.join(ruta, '.listo')).existsSync(), isTrue);
  });
}

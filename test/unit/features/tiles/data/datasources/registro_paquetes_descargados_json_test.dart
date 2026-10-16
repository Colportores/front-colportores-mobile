// Test de data: el manifiesto `registro.json` contra un directorio temporal real.
import 'dart:convert';
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/datasources/registro_paquetes_descargados_json.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/tiles_falsos.dart';

void main() {
  late Directory temporal;
  late Directory directorio;
  late RegistroPaquetesDescargadosJson registro;

  PaqueteDescargado paquete(String id, {int semilla = 5}) {
    final d = descargadoDe(paqueteDe(bytesDePrueba(10, semilla: semilla), id: id));
    return PaqueteDescargado(
      paquete: d.paquete,
      rutas: [p.join(directorio.path, '${d.paquete.claveDeParte(0)}.pmtiles')],
    );
  }

  File manifiesto() => File(p.join(directorio.path, RegistroPaquetesDescargadosJson.nombreArchivo));

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('registro_test_');
    directorio = Directory(p.join(temporal.path, 'tiles'));
    registro = RegistroPaquetesDescargadosJson(directorio, logger: loggerMudo());
  });

  tearDown(() => temporal.delete(recursive: true));

  test('sin manifiesto (ni directorio) no hay paquetes, y leer no crea nada', () async {
    expect(await registro.leer(), isEmpty);
    expect(directorio.existsSync(), isFalse);
  });

  test('guardar crea el directorio y el manifiesto, y leer devuelve lo guardado', () async {
    final zona = paquete('zona-centro');

    await registro.guardar(zona);

    expect(manifiesto().existsSync(), isTrue);
    expect(await registro.leer(), [zona]);
  });

  test('sobrevive a una sesión nueva: otro registro sobre la misma carpeta lee lo mismo', () async {
    final zona = paquete('zona-centro');
    await registro.guardar(zona);

    final otro = RegistroPaquetesDescargadosJson(directorio, logger: loggerMudo());

    expect(await otro.leer(), [zona]);
  });

  test('guardar un paquete con el mismo id lo reemplaza, en su lugar', () async {
    final a = paquete('a');
    final b = paquete('b');
    final a2 = paquete('a', semilla: 9);
    await registro.guardar(a);
    await registro.guardar(b);

    await registro.guardar(a2);

    expect(await registro.leer(), [a2, b]);
  });

  test('quitar saca solo ese paquete; quitar uno que no está no cambia nada', () async {
    final a = paquete('a');
    final b = paquete('b');
    await registro.guardar(a);
    await registro.guardar(b);

    await registro.quitar('a');
    final despuesDeQuitar = await manifiesto().readAsString();
    await registro.quitar('no-esta');

    expect(await registro.leer(), [b]);
    expect(await manifiesto().readAsString(), despuesDeQuitar);
  });

  test('no deja un .tmp atrás: la escritura es un rename del archivo temporal', () async {
    await registro.guardar(paquete('a'));
    await registro.quitar('a');

    final nombres = directorio.listSync().map((e) => p.basename(e.path)).toList();

    expect(nombres, ['registro.json']);
  });

  test('un .tmp que quedó de un corte no afecta la lectura', () async {
    final zona = paquete('zona-centro');
    await registro.guardar(zona);
    await File('${manifiesto().path}.tmp').writeAsString('{"version":1,"paq');

    expect(await registro.leer(), [zona]);
  });

  test('operaciones al mismo tiempo no se pisan: se hacen de a una', () async {
    final paquetes = [for (var i = 0; i < 12; i++) paquete('p$i')];

    await Future.wait([for (final d in paquetes) registro.guardar(d)]);

    final leidos = await registro.leer();
    expect(leidos.map((d) => d.id).toSet(), paquetes.map((d) => d.id).toSet());
    expect(leidos, hasLength(12));
  });

  test('guardar y quitar seguidos, sin esperar, terminan en el orden pedido', () async {
    final a = paquete('a');

    await Future.wait([registro.guardar(a), registro.quitar('a'), registro.guardar(a)]);

    expect(await registro.leer(), [a]);
  });

  group('un manifiesto roto', () {
    test('que no es JSON cuenta como vacío y el próximo guardar lo repara', () async {
      await directorio.create(recursive: true);
      await manifiesto().writeAsString('{"version":1,"paq');

      expect(await registro.leer(), isEmpty);

      final zona = paquete('zona-centro');
      await registro.guardar(zona);
      expect(await registro.leer(), [zona]);
    });

    test('vacío o sin la lista de paquetes cuenta como vacío', () async {
      await directorio.create(recursive: true);
      for (final texto in ['', '[]', '{}', '{"paquetes":"x"}']) {
        await manifiesto().writeAsString(texto);

        expect(await registro.leer(), isEmpty, reason: texto);
      }
    });

    test('con una entrada mala, se pierde solo esa', () async {
      final buena = paquete('buena');
      await registro.guardar(buena);
      final json = jsonDecode(await manifiesto().readAsString()) as Map<String, dynamic>;
      (json['paquetes'] as List<dynamic>)
        ..insert(0, {'paquete': 'x'})
        ..add(5);
      await manifiesto().writeAsString(jsonEncode(json));

      expect(await registro.leer(), [buena]);
    });
  });
}

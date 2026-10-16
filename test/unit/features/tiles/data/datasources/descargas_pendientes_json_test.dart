// Test de data: el manifiesto `descargas_pendientes.json` contra un directorio temporal real.
import 'dart:convert';
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/datasources/descargas_pendientes_json.dart';
import 'package:colportores_mobile/features/tiles/data/datasources/registro_paquetes_descargados_json.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/descarga_pendiente.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/tiles_falsos.dart';

void main() {
  late Directory temporal;
  late Directory directorio;
  late DescargasPendientesJson pendientes;

  DescargaPendiente descarga(String id, {int semilla = 5, bool datos = false}) {
    return DescargaPendiente(
      paquete: paqueteDe(bytesDePrueba(10, semilla: semilla), id: id),
      anotadaEn: DateTime.utc(2026, 10, 7, 12),
      permitirDatosMoviles: datos,
    );
  }

  File manifiesto() => File(p.join(directorio.path, DescargasPendientesJson.nombreArchivo));

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('pendientes_test_');
    directorio = Directory(p.join(temporal.path, 'tiles'));
    pendientes = DescargasPendientesJson(directorio, logger: loggerMudo());
  });

  tearDown(() => temporal.delete(recursive: true));

  test('el manifiesto va junto a registro.json, con otro nombre', () {
    expect(DescargasPendientesJson.nombreArchivo, 'descargas_pendientes.json');
    expect(
      DescargasPendientesJson.nombreArchivo,
      isNot(RegistroPaquetesDescargadosJson.nombreArchivo),
    );
  });

  test('sin manifiesto (ni directorio) no hay descargas, y leer no crea nada', () async {
    expect(await pendientes.leer(), isEmpty);
    expect(directorio.existsSync(), isFalse);
  });

  test('guardar crea el directorio y el manifiesto, y leer devuelve lo guardado', () async {
    final zona = descarga('zona-centro', datos: true);

    await pendientes.guardar(zona);

    expect(manifiesto().existsSync(), isTrue);
    expect(await pendientes.leer(), [zona]);
  });

  test('sobrevive a un reinicio: otro lector sobre la misma carpeta lee lo mismo', () async {
    final zona = descarga('zona-centro');
    await pendientes.guardar(zona);

    final otro = DescargasPendientesJson(directorio, logger: loggerMudo());

    expect(await otro.leer(), [zona]);
  });

  test('guardar una descarga con el mismo id la reemplaza, en su lugar', () async {
    final a = descarga('a');
    final b = descarga('b');
    final a2 = descarga('a', semilla: 9, datos: true);
    await pendientes.guardar(a);
    await pendientes.guardar(b);

    await pendientes.guardar(a2);

    expect(await pendientes.leer(), [a2, b]);
  });

  test('quitar saca solo esa descarga; quitar una que no está no cambia nada', () async {
    await pendientes.guardar(descarga('a'));
    final b = descarga('b');
    await pendientes.guardar(b);

    await pendientes.quitar('a');
    final despuesDeQuitar = await manifiesto().readAsString();
    await pendientes.quitar('no-esta');

    expect(await pendientes.leer(), [b]);
    expect(await manifiesto().readAsString(), despuesDeQuitar);
  });

  test('no deja un .tmp atrás: la escritura es un rename del archivo temporal', () async {
    await pendientes.guardar(descarga('a'));
    await pendientes.quitar('a');

    final nombres = directorio.listSync().map((e) => p.basename(e.path)).toList();

    expect(nombres, [DescargasPendientesJson.nombreArchivo]);
  });

  test('un .tmp que quedó de un corte no afecta la lectura', () async {
    final zona = descarga('zona-centro');
    await pendientes.guardar(zona);
    await File('${manifiesto().path}.tmp').writeAsString('{"version":1,"desc');

    expect(await pendientes.leer(), [zona]);
  });

  test('operaciones al mismo tiempo no se pisan: se hacen de a una', () async {
    final todas = [for (var i = 0; i < 12; i++) descarga('p$i')];

    await Future.wait([for (final d in todas) pendientes.guardar(d)]);

    final leidas = await pendientes.leer();
    expect(leidas.map((d) => d.id).toSet(), todas.map((d) => d.id).toSet());
    expect(leidas, hasLength(12));
  });

  test('guardar y quitar seguidos, sin esperar, terminan en el orden pedido', () async {
    final a = descarga('a');

    await Future.wait([pendientes.guardar(a), pendientes.quitar('a'), pendientes.guardar(a)]);

    expect(await pendientes.leer(), [a]);
  });

  test('no se pisa con el registro de los descargados: cada uno tiene su archivo', () async {
    final registro = RegistroPaquetesDescargadosJson(directorio, logger: loggerMudo());
    final zona = descarga('zona-centro');
    await pendientes.guardar(zona);

    await registro.guardar(descargadoDe(zona.paquete));
    await pendientes.quitar('zona-centro');

    expect(await registro.leer(), hasLength(1));
    expect(await pendientes.leer(), isEmpty);
  });

  group('un manifiesto roto', () {
    test('que no es JSON cuenta como vacío y el próximo guardar lo repara', () async {
      await directorio.create(recursive: true);
      await manifiesto().writeAsString('{"version":1,"desc');

      expect(await pendientes.leer(), isEmpty);

      final zona = descarga('zona-centro');
      await pendientes.guardar(zona);
      expect(await pendientes.leer(), [zona]);
    });

    test('vacío o sin la lista de descargas cuenta como vacío', () async {
      await directorio.create(recursive: true);
      for (final texto in ['', '[]', '{}', '{"descargas":"x"}']) {
        await manifiesto().writeAsString(texto);

        expect(await pendientes.leer(), isEmpty, reason: texto);
      }
    });

    test('con una entrada mala, se pierde solo esa', () async {
      final buena = descarga('buena');
      await pendientes.guardar(buena);
      final json = jsonDecode(await manifiesto().readAsString()) as Map<String, dynamic>;
      (json['descargas'] as List<dynamic>)
        ..insert(0, {'paquete': 'x'})
        ..add(5);
      await manifiesto().writeAsString(jsonEncode(json));

      expect(await pendientes.leer(), [buena]);
    });
  });
}

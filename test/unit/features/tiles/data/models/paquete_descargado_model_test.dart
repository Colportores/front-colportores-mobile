// Test de data: el paquete descargado como entrada del manifiesto `registro.json`.
import 'dart:convert';

import 'package:colportores_mobile/features/tiles/data/models/paquete_descargado_model.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../../../helpers/tiles_falsos.dart';

void main() {
  final directorio = p.join('/data', 'tiles');
  final partes = [bytesDePrueba(8), bytesDePrueba(6, semilla: 9)];
  final paquete = paqueteEnPartes(partes);
  final descargado = PaqueteDescargado(
    paquete: paquete,
    rutas: [
      p.join(directorio, '${paquete.claveDeParte(0)}.pmtiles'),
      p.join(directorio, '${paquete.claveDeParte(1)}.pmtiles'),
    ],
  );

  /// Lo que se escribe, pasado por JSON de verdad (como en el disco).
  Map<String, dynamic> viaje() =>
      jsonDecode(jsonEncode(PaqueteDescargadoModel.aJson(descargado))) as Map<String, dynamic>;

  test('ida y vuelta: lo que se guarda es lo que se lee, con las rutas en el directorio', () {
    final leido = PaqueteDescargadoModel.desdeJson(viaje(), directorio);

    expect(leido, descargado);
    expect(leido.paquete.partes.map((x) => x.origen), paquete.partes.map((x) => x.origen));
    expect(leido.paquete.nombre, paquete.nombre);
  });

  test('el manifiesto guarda solo el nombre de cada archivo, no la carpeta', () {
    final json = viaje();

    expect(json['archivos'], [
      '${paquete.claveDeParte(0)}.pmtiles',
      '${paquete.claveDeParte(1)}.pmtiles',
    ]);
  });

  test('si la carpeta de la app cambió, las rutas salen de la nueva', () {
    final leido = PaqueteDescargadoModel.desdeJson(viaje(), p.join('/otra', 'carpeta'));

    expect(leido.rutas.first, p.join('/otra', 'carpeta', '${paquete.claveDeParte(0)}.pmtiles'));
  });

  test('un paquete sin nombre ni ámbito (Uruguay) vuelve igual', () {
    final uruguay = PaqueteTiles(
      id: 'uruguay',
      nivel: NivelCobertura.uruguay,
      ambitoId: null,
      version: 'v1',
      partes: [paquete.partes.first],
    );
    final d = PaqueteDescargado(
      paquete: uruguay,
      rutas: [p.join(directorio, 'uruguay-p1-abc.pmtiles')],
    );

    final leido = PaqueteDescargadoModel.desdeJson(
      jsonDecode(jsonEncode(PaqueteDescargadoModel.aJson(d))),
      directorio,
    );

    expect(leido.paquete.ambitoId, isNull);
    expect(leido.paquete.nombre, isNull);
    expect(leido, d);
  });

  group('una entrada que no se puede leer lanza FormatException', () {
    void rota(String caso, void Function(Map<String, dynamic> json) romper) {
      test(caso, () {
        final json = viaje();
        romper(json);

        expect(() => PaqueteDescargadoModel.desdeJson(json, directorio), throwsFormatException);
      });
    }

    Map<String, dynamic> paq(Map<String, dynamic> json) => json['paquete'] as Map<String, dynamic>;

    test('que no es un objeto', () {
      expect(() => PaqueteDescargadoModel.desdeJson('x', directorio), throwsFormatException);
      expect(() => PaqueteDescargadoModel.desdeJson(null, directorio), throwsFormatException);
    });

    rota('sin paquete', (j) => j.remove('paquete'));
    rota('sin archivos', (j) => j.remove('archivos'));
    rota('con más archivos que partes', (j) => (j['archivos'] as List<dynamic>).add('x.pmtiles'));
    rota('con menos archivos que partes', (j) => (j['archivos'] as List<dynamic>).removeLast());
    rota('sin partes', (j) {
      paq(j)['partes'] = <Object?>[];
      j['archivos'] = <Object?>[];
    });
    rota('con un nivel que no existe', (j) => paq(j)['nivel'] = 'planeta');
    rota('sin id', (j) => paq(j).remove('id'));
    rota('sin versión', (j) => paq(j).remove('version'));
    rota('con una parte que no es un objeto', (j) => (paq(j)['partes'] as List<dynamic>)[0] = 5);
    rota('con una parte sin tamaño', (j) {
      ((paq(j)['partes'] as List<dynamic>)[0] as Map<String, dynamic>).remove('tamano_bytes');
    });
    rota('con una parte sin sha256', (j) {
      ((paq(j)['partes'] as List<dynamic>)[0] as Map<String, dynamic>).remove('sha256');
    });
    rota('con una parte sin origen', (j) {
      ((paq(j)['partes'] as List<dynamic>)[0] as Map<String, dynamic>).remove('origen');
    });
    rota('con un archivo que es una ruta (no se sale del directorio)', (j) {
      (j['archivos'] as List<dynamic>)[0] = '../../etc/passwd';
    });
    rota('con un archivo vacío', (j) => (j['archivos'] as List<dynamic>)[0] = '');
    rota('con un archivo que no es texto', (j) => (j['archivos'] as List<dynamic>)[0] = 7);
  });
}

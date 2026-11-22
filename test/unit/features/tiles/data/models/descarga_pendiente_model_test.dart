// Test de data: la descarga pendiente como entrada del manifiesto `descargas_pendientes.json`.
import 'dart:convert';

import 'package:colportores_mobile/features/tiles/data/models/descarga_pendiente_model.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/descarga_pendiente.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:test/test.dart';

import '../../../../../helpers/tiles_falsos.dart';

void main() {
  final paquete = paqueteEnPartes([bytesDePrueba(8), bytesDePrueba(6, semilla: 9)]);
  final pendiente = DescargaPendiente(
    paquete: paquete,
    anotadaEn: DateTime.utc(2026, 10, 7, 12, 30),
    permitirDatosMoviles: true,
  );

  /// Lo que se escribe, pasado por JSON de verdad (como en el disco).
  Map<String, dynamic> viaje([DescargaPendiente? cual]) =>
      jsonDecode(jsonEncode(DescargaPendienteModel.aJson(cual ?? pendiente)))
          as Map<String, dynamic>;

  test('ida y vuelta: guarda el paquete con que empezó, con la dirección, el tamaño y la huella '
      'de cada parte', () {
    final leida = DescargaPendienteModel.desdeJson(viaje());

    expect(leida, pendiente);
    expect(leida.paquete.partes.map((x) => x.origen), paquete.partes.map((x) => x.origen));
    expect(leida.paquete.partes.map((x) => x.tamanoBytes), [8, 6]);
    expect(leida.paquete.partes.map((x) => x.huella), paquete.partes.map((x) => x.huella));
    expect(leida.paquete.nombre, paquete.nombre);
  });

  test('guarda los dos permisos', () {
    final pausada = DescargaPendiente(
      paquete: paquete,
      anotadaEn: pendiente.anotadaEn,
      pausadaPorElColportor: true,
    );

    final leida = DescargaPendienteModel.desdeJson(viaje(pausada));

    expect(leida.permitirDatosMoviles, isFalse);
    expect(leida.pausadaPorElColportor, isTrue);
  });

  test('la fecha se guarda en UTC y vuelve como el mismo instante', () {
    final local = DescargaPendiente(paquete: paquete, anotadaEn: DateTime(2026, 10, 7, 12));

    final leida = DescargaPendienteModel.desdeJson(viaje(local));

    expect(leida.anotadaEn.isAtSameMomentAs(local.anotadaEn), isTrue);
    expect(viaje(local)['anotada_en'], endsWith('Z'));
  });

  test('un paquete sin nombre ni ámbito (Uruguay) vuelve igual', () {
    final uruguay = PaqueteTiles(
      id: 'uruguay',
      nivel: NivelCobertura.uruguay,
      ambitoId: null,
      version: 'v1',
      partes: [paquete.partes.first],
    );
    final p = DescargaPendiente(paquete: uruguay, anotadaEn: pendiente.anotadaEn);

    expect(DescargaPendienteModel.desdeJson(viaje(p)), p);
  });

  group('lo que no se entiende lanza FormatException', () {
    void esRechazado(Map<String, dynamic> Function(Map<String, dynamic> json) romper) {
      expect(
        () => DescargaPendienteModel.desdeJson(romper(viaje())),
        throwsA(isA<FormatException>()),
      );
    }

    test('que no sea un objeto', () {
      expect(() => DescargaPendienteModel.desdeJson(5), throwsA(isA<FormatException>()));
      expect(() => DescargaPendienteModel.desdeJson(null), throwsA(isA<FormatException>()));
    });

    test('sin paquete', () => esRechazado((json) => json..remove('paquete')));

    test('con una fecha ilegible', () => esRechazado((json) => json..['anotada_en'] = 'ayer'));

    test('sin fecha', () => esRechazado((json) => json..remove('anotada_en')));

    test('con un permiso que no es verdadero ni falso', () {
      esRechazado((json) => json..['permitir_datos_moviles'] = 'si');
      esRechazado((json) => json..['pausada_por_el_colportor'] = null);
    });

    test('con un paquete sin partes', () {
      esRechazado((json) {
        (json['paquete'] as Map<String, dynamic>)['partes'] = <Object?>[];
        return json;
      });
    });

    test('con un nivel que no existe', () {
      esRechazado((json) {
        (json['paquete'] as Map<String, dynamic>)['nivel'] = 'planeta';
        return json;
      });
    });

    test('con una parte sin tamaño', () {
      esRechazado((json) {
        final partes = (json['paquete'] as Map<String, dynamic>)['partes'] as List<dynamic>;
        (partes.first as Map<String, dynamic>).remove('tamano_bytes');
        return json;
      });
    });
  });
}

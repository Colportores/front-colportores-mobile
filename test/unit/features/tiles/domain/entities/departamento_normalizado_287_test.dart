// Test de dominio: Dart puro. El departamento se elige por su nombre normalizado (#287, decisión de
// Cristian, 23/10, «Área depto»): el `ambito_id` del paquete es `san jose`, `rio negro`.
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:test/test.dart';

import '../../../../../helpers/tiles_falsos.dart';

void main() {
  group('normalizarDepartamento', () {
    test('quita tildes, pasa a minúsculas y colapsa los espacios', () {
      expect(normalizarDepartamento('San José'), 'san jose');
      expect(normalizarDepartamento('  Río   Negro '), 'rio negro');
      expect(normalizarDepartamento('Paysandú'), 'paysandu');
      expect(normalizarDepartamento('Tacuarembó'), 'tacuarembo');
      expect(normalizarDepartamento('TREINTA Y TRES'), 'treinta y tres');
      expect(normalizarDepartamento('Cerro\tLargo'), 'cerro largo');
    });

    test('un nombre ya normalizado queda igual y uno vacío queda vacío', () {
      expect(normalizarDepartamento('canelones'), 'canelones');
      expect(normalizarDepartamento('   '), '');
    });
  });

  group('PaqueteTiles.cubre — departamento', () {
    final bytes = bytesDePrueba(10);
    PaqueteTiles deptoSanJose() => paqueteDe(
      bytes,
      id: 'depto-san-jose',
      nivel: NivelCobertura.departamento,
      ambitoId: 'san jose',
    );

    test('lo cubre aunque la ciudad lo nombre con tildes y mayúsculas', () {
      expect(deptoSanJose().cubre(const AmbitoTrabajo(departamentoId: 'San José')), isTrue);
      expect(deptoSanJose().cubre(const AmbitoTrabajo(departamentoId: 'san jose')), isTrue);
    });

    test('no cubre otro departamento, ni uno sin dato, ni uno vacío', () {
      expect(deptoSanJose().cubre(const AmbitoTrabajo(departamentoId: 'Rocha')), isFalse);
      expect(deptoSanJose().cubre(const AmbitoTrabajo(ciudadId: 'c-1')), isFalse);
      expect(deptoSanJose().cubre(const AmbitoTrabajo(departamentoId: '  ')), isFalse);
    });

    test('un paquete de departamento sin ambito_id no cubre a nadie', () {
      final sinAmbito = PaqueteTiles(
        id: 'depto-x',
        nivel: NivelCobertura.departamento,
        ambitoId: null,
        version: 'v1',
        partes: deptoSanJose().partes,
      );
      expect(sinAmbito.cubre(const AmbitoTrabajo(departamentoId: 'san jose')), isFalse);
    });

    test('la ciudad y la zona siguen comparando el id tal cual', () {
      final ciudad = paqueteDe(
        bytes,
        id: 'ciudad-x',
        nivel: NivelCobertura.ciudad,
        ambitoId: 'c-1',
      );
      expect(ciudad.cubre(const AmbitoTrabajo(ciudadId: 'c-1')), isTrue);
      expect(ciudad.cubre(const AmbitoTrabajo(ciudadId: 'C-1')), isFalse);
    });

    test('Uruguay cubre cualquier lugar, también uno desconocido', () {
      final uruguay = paqueteDe(
        bytes,
        id: 'uruguay',
        nivel: NivelCobertura.uruguay,
        ambitoId: null,
      );
      expect(uruguay.cubre(const AmbitoTrabajo()), isTrue);
      expect(uruguay.cubre(const AmbitoTrabajo(departamentoId: 'Rocha')), isTrue);
    });
  });
}

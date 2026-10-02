// Test de dominio: Dart puro (HU-UBI-001, vista 03).
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:test/test.dart';

void main() {
  group('DireccionDelPunto', () {
    test('está vacía sin calle ni número, o con ambos en blanco', () {
      expect(const DireccionDelPunto().estaVacia, isTrue);
      expect(const DireccionDelPunto(calle: '  ', numero: '').estaVacia, isTrue);
    });

    test('no está vacía con la calle o con el número', () {
      expect(const DireccionDelPunto(calle: 'Av. Italia').estaVacia, isFalse);
      expect(const DireccionDelPunto(numero: '1234').estaVacia, isFalse);
    });

    test('dos direcciones con lo mismo son iguales', () {
      expect(
        const DireccionDelPunto(calle: 'Av. Italia', numero: '1'),
        const DireccionDelPunto(calle: 'Av. Italia', numero: '1'),
      );
      expect(
        const DireccionDelPunto(calle: 'Av. Italia', numero: '1'),
        isNot(const DireccionDelPunto(calle: 'Av. Italia', numero: '2')),
      );
    });
  });

  group('DeteccionCiudad', () {
    const montevideo = CiudadCatalogo(id: 'm', nombre: 'Montevideo');
    const canelones = CiudadCatalogo(id: 'c', nombre: 'Canelones');

    test('cada resultado se compara por su contenido', () {
      expect(const CiudadDetectada(montevideo), const CiudadDetectada(montevideo));
      expect(const CiudadDetectada(montevideo), isNot(const CiudadDetectada(canelones)));
      expect(
        const CiudadAmbigua([montevideo, canelones]),
        const CiudadAmbigua([montevideo, canelones]),
      );
      expect(const CiudadNoEncontrada(), const CiudadNoEncontrada());
      expect(const CiudadNoEncontrada(), isNot(const CiudadDetectada(montevideo)));
    });

    test('un switch sobre el resultado es exhaustivo', () {
      String texto(DeteccionCiudad d) => switch (d) {
        CiudadDetectada(:final ciudad) => 'detectada ${ciudad.nombre}',
        CiudadAmbigua(:final candidatas) => 'ambigua ${candidatas.length}',
        CiudadNoEncontrada() => 'no encontrada',
      };

      expect(texto(const CiudadDetectada(montevideo)), 'detectada Montevideo');
      expect(texto(const CiudadAmbigua([montevideo, canelones])), 'ambigua 2');
      expect(texto(const CiudadNoEncontrada()), 'no encontrada');
    });
  });
}

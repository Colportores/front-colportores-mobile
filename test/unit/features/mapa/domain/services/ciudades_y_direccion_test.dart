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

  group('PropuestaCiudad', () {
    const montevideo = CiudadCatalogo(id: 'm', nombre: 'Montevideo');
    const canelones = CiudadCatalogo(id: 'c', nombre: 'Canelones');

    test('cada propuesta se compara por su contenido', () {
      expect(
        const CiudadPropuesta(montevideo, OrigenPropuesta.detectada),
        const CiudadPropuesta(montevideo, OrigenPropuesta.detectada),
      );
      expect(
        const CiudadPropuesta(montevideo, OrigenPropuesta.detectada),
        isNot(const CiudadPropuesta(canelones, OrigenPropuesta.detectada)),
      );
      expect(
        const CiudadPropuesta(montevideo, OrigenPropuesta.detectada),
        isNot(const CiudadPropuesta(montevideo, OrigenPropuesta.deZona)),
      );
      expect(const CampaniaSinCiudades(), const CampaniaSinCiudades());
      expect(const FaltaElPunto(), const FaltaElPunto());
      expect(const CampaniaSinCiudades(), isNot(const FaltaElPunto()));
    });

    test('un switch sobre la propuesta es exhaustivo: no hay «no encontrada» ni «ambigua»', () {
      String texto(PropuestaCiudad p) => switch (p) {
        CiudadPropuesta(:final ciudad, :final origen) => '${origen.name} ${ciudad.nombre}',
        CampaniaSinCiudades() => 'sin ciudades',
        FaltaElPunto() => 'falta el punto',
      };

      expect(
        texto(const CiudadPropuesta(montevideo, OrigenPropuesta.deCampania)),
        'deCampania Montevideo',
      );
      expect(texto(const CampaniaSinCiudades()), 'sin ciudades');
      expect(texto(const FaltaElPunto()), 'falta el punto');
    });
  });
}

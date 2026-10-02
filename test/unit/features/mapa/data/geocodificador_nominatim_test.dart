import 'package:colportores_mobile/features/mapa/data/services/geocodificador_nominatim.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:flutter_test/flutter_test.dart';

const _punto = Coordenadas(lat: -34.88761, lon: -56.13024);

void main() {
  group('interpretar', () {
    test('toma la calle y el número', () {
      final d = GeocodificadorNominatim.interpretar(
        '{"address":{"road":"Avenida Italia","house_number":"1234","city":"Montevideo"}}',
      );
      expect(d, const DireccionDelPunto(calle: 'Avenida Italia', numero: '1234'));
    });

    test('sin número, queda la calle', () {
      final d = GeocodificadorNominatim.interpretar('{"address":{"road":"Avenida Italia"}}');
      expect(d, const DireccionDelPunto(calle: 'Avenida Italia'));
    });

    test('una peatonal cuenta como calle', () {
      final d = GeocodificadorNominatim.interpretar('{"address":{"pedestrian":"Sarandí"}}');
      expect(d?.calle, 'Sarandí');
    });

    test('sin calle ni número, no hay dirección', () {
      expect(GeocodificadorNominatim.interpretar('{"address":{"city":"Montevideo"}}'), isNull);
      expect(
        GeocodificadorNominatim.interpretar('{"address":{"road":"  ","house_number":""}}'),
        isNull,
      );
    });

    test('una respuesta que no es lo esperado, no hay dirección', () {
      expect(GeocodificadorNominatim.interpretar('[]'), isNull);
      expect(GeocodificadorNominatim.interpretar('{"error":"Unable to geocode"}'), isNull);
      expect(GeocodificadorNominatim.interpretar('{"address":"x"}'), isNull);
    });
  });

  group('direccionDe', () {
    test('pide la geocodificación inversa con las coordenadas y devuelve la dirección', () async {
      Uri? pedida;
      final g = GeocodificadorNominatim((url) async {
        pedida = url;
        return '{"address":{"road":"Avenida Italia","house_number":"1234"}}';
      });

      final d = await g.direccionDe(_punto);

      expect(d, const DireccionDelPunto(calle: 'Avenida Italia', numero: '1234'));
      expect(pedida?.host, 'nominatim.openstreetmap.org');
      expect(pedida?.path, '/reverse');
      expect(pedida?.queryParameters['lat'], '-34.88761');
      expect(pedida?.queryParameters['lon'], '-56.13024');
      expect(pedida?.queryParameters['accept-language'], 'es');
    });

    test('sin red (el lector devuelve null), no hay dirección', () async {
      expect(await GeocodificadorNominatim((_) async => null).direccionDe(_punto), isNull);
    });

    test('un cuerpo ilegible o un lector que lanza no lanzan', () async {
      expect(await GeocodificadorNominatim((_) async => 'no es json').direccionDe(_punto), isNull);
      expect(
        await GeocodificadorNominatim((_) async => throw StateError('boom')).direccionDe(_punto),
        isNull,
      );
    });
  });
}

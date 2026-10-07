// Test de dominio: Dart puro (HU-UBI-003, #286): el radio de precisión como polígono y de dónde sale
// el mapa.
import 'package:colportores_mobile/features/mapa/domain/services/circulo_geografico.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:test/test.dart';

void main() {
  const montevideo = Coordenadas(lat: -34.88761, lon: -56.13024);

  group('CirculoGeografico.anillo', () {
    test('es un anillo cerrado: el último vértice repite al primero', () {
      final anillo = CirculoGeografico.anillo(montevideo, 25);

      expect(anillo, hasLength(65));
      expect(anillo.last, anillo.first);
    });

    test('cada vértice está a la distancia pedida del centro', () {
      for (final radio in [3.0, 25.0, 400.0]) {
        final anillo = CirculoGeografico.anillo(montevideo, radio);
        for (final vertice in anillo) {
          expect(montevideo.distanciaMetrosA(vertice), closeTo(radio, radio * 0.001));
        }
      }
    });

    test('empieza al norte del centro y sigue en sentido horario', () {
      final anillo = CirculoGeografico.anillo(montevideo, 100, lados: 4);

      // Norte, este, sur, oeste y de vuelta al norte.
      expect(anillo, hasLength(5));
      expect(anillo[0].lat, greaterThan(montevideo.lat));
      expect(anillo[0].lon, closeTo(montevideo.lon, 1e-9));
      expect(anillo[1].lon, greaterThan(montevideo.lon));
      expect(anillo[2].lat, lessThan(montevideo.lat));
      expect(anillo[3].lon, lessThan(montevideo.lon));
    });

    test('la cantidad de lados es la pedida', () {
      expect(CirculoGeografico.anillo(montevideo, 10, lados: 8), hasLength(9));
    });

    test('sin un radio finito mayor que cero no hay nada que dibujar', () {
      expect(CirculoGeografico.anillo(montevideo, 0), isEmpty);
      expect(CirculoGeografico.anillo(montevideo, -5), isEmpty);
      expect(CirculoGeografico.anillo(montevideo, double.nan), isEmpty);
      expect(CirculoGeografico.anillo(montevideo, double.infinity), isEmpty);
    });

    test('un centro inválido tampoco dibuja nada', () {
      expect(CirculoGeografico.anillo(const Coordenadas(lat: 91, lon: 0), 10), isEmpty);
      expect(CirculoGeografico.anillo(const Coordenadas(lat: 0, lon: -181), 10), isEmpty);
      expect(CirculoGeografico.anillo(const Coordenadas(lat: double.nan, lon: 0), 10), isEmpty);
      expect(CirculoGeografico.anillo(const Coordenadas(lat: 0, lon: double.nan), 10), isEmpty);
    });

    test('cerca del antimeridiano las longitudes siguen en [-180, 180]', () {
      final anillo = CirculoGeografico.anillo(const Coordenadas(lat: 0, lon: 179.9999), 50000);

      expect(anillo.every((v) => v.lon >= -180 && v.lon <= 180), isTrue);
      expect(anillo.any((v) => v.lon < 0), isTrue);
      expect(anillo.any((v) => v.lon > 0), isTrue);
    });
  });

  group('FuenteMapa', () {
    test('sin tiles no hay URL y no hay tiles', () {
      const fuente = FuenteMapa.sinTiles();

      expect(fuente.tipo, FuenteTiles.sinTiles);
      expect(fuente.urlPmtiles, isNull);
      expect(fuente.hayTiles, isFalse);
    });

    test('el paquete descargado se abre con file:// adentro de pmtiles://', () {
      const fuente = FuenteMapa.offline('/data/user/0/app/files/paquetes/uruguay.pmtiles');

      expect(fuente.tipo, FuenteTiles.pmtilesOffline);
      expect(fuente.urlPmtiles, 'pmtiles://file:///data/user/0/app/files/paquetes/uruguay.pmtiles');
      expect(fuente.hayTiles, isTrue);
    });

    test('el servidor se abre con pmtiles:// delante de la URL', () {
      const fuente = FuenteMapa.online(
        'https://x.supabase.co/storage/v1/object/public/mapas/uy.pmtiles',
      );

      expect(fuente.tipo, FuenteTiles.servidorOnline);
      expect(
        fuente.urlPmtiles,
        'pmtiles://https://x.supabase.co/storage/v1/object/public/mapas/uy.pmtiles',
      );
      expect(fuente.hayTiles, isTrue);
    });

    test('un paquete en partes se abre con una URL por parte, en el orden del catálogo', () {
      const offline = FuenteMapa.offlineEnPartes(['/data/mvd-p1.pmtiles', '/data/mvd-p2.pmtiles']);
      const online = FuenteMapa.onlineEnPartes([
        'https://s/mvd-p1.pmtiles',
        'https://s/mvd-p2.pmtiles',
      ]);

      expect(offline.tipo, FuenteTiles.pmtilesOffline);
      expect(offline.origenes, ['/data/mvd-p1.pmtiles', '/data/mvd-p2.pmtiles']);
      expect(offline.urlsPmtiles, [
        'pmtiles://file:///data/mvd-p1.pmtiles',
        'pmtiles://file:///data/mvd-p2.pmtiles',
      ]);
      expect(offline.urlPmtiles, 'pmtiles://file:///data/mvd-p1.pmtiles');
      expect(online.tipo, FuenteTiles.servidorOnline);
      expect(online.urlsPmtiles, [
        'pmtiles://https://s/mvd-p1.pmtiles',
        'pmtiles://https://s/mvd-p2.pmtiles',
      ]);
      expect(const FuenteMapa.sinTiles().urlsPmtiles, isEmpty);
      expect(const FuenteMapa.sinTiles().origenes, isEmpty);
    });

    test('es un valor: igual por tipo y origen', () {
      expect(const FuenteMapa.offline('/a'), const FuenteMapa.offline('/a'));
      expect(const FuenteMapa.offline('/a'), const FuenteMapa.offlineEnPartes(['/a']));
      expect(const FuenteMapa.offline('/a'), isNot(const FuenteMapa.offline('/b')));
      expect(const FuenteMapa.offline('/a'), isNot(const FuenteMapa.online('/a')));
      expect(
        const FuenteMapa.offlineEnPartes(['/a', '/b']),
        isNot(const FuenteMapa.offlineEnPartes(['/b', '/a'])),
      );
      expect(const FuenteMapa.sinTiles(), const FuenteMapa.sinTiles());
    });

    group('resolver', () {
      const rutas = ['/data/paquete.pmtiles'];
      const urls = ['https://servidor/uy.pmtiles'];

      test('con el paquete descargado manda el paquete, haya red o no', () {
        for (final hayRed in [true, false]) {
          expect(
            FuenteMapa.resolver(rutasOffline: rutas, urlsOnline: urls, hayRed: hayRed),
            const FuenteMapa.offline('/data/paquete.pmtiles'),
          );
        }
      });

      test('con el paquete descargado en partes manda las partes, en orden', () {
        expect(
          FuenteMapa.resolver(rutasOffline: const ['/a', '/b'], hayRed: false),
          const FuenteMapa.offlineEnPartes(['/a', '/b']),
        );
      });

      test('sin paquete y con red va al servidor', () {
        expect(
          FuenteMapa.resolver(urlsOnline: urls, hayRed: true),
          const FuenteMapa.online('https://servidor/uy.pmtiles'),
        );
        expect(
          FuenteMapa.resolver(urlsOnline: const ['https://s/a', 'https://s/b'], hayRed: true),
          const FuenteMapa.onlineEnPartes(['https://s/a', 'https://s/b']),
        );
      });

      test('sin paquete, con red pero con el servidor caído no hay tiles', () {
        expect(
          FuenteMapa.resolver(urlsOnline: urls, hayRed: true, servidorOnlineDisponible: false),
          const FuenteMapa.sinTiles(),
        );
      });

      test('sin paquete y sin red no hay tiles', () {
        expect(FuenteMapa.resolver(urlsOnline: urls, hayRed: false), const FuenteMapa.sinTiles());
      });

      test('sin URL no hay a dónde ir, aunque haya red', () {
        expect(FuenteMapa.resolver(hayRed: true), const FuenteMapa.sinTiles());
      });
    });
  });
}

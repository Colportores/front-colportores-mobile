// Test de dominio: Dart puro (HU-UBI-003): área, agrupador, fuente de tiles y centro del mapa.
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/agrupador_marcadores.dart';
import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:test/test.dart';

void main() {
  MarcadorMapa m(String id, double lat, double lon, {int espacios = 0}) => MarcadorMapa(
    ubicacionId: id,
    tipo: TipoUbicacion.casa,
    lat: lat,
    lon: lon,
    cantidadEspacios: espacios,
  );

  group('AreaMapa', () {
    const area = AreaMapa(sur: -35, oeste: -57, norte: -34, este: -56);

    test('contiene los puntos de adentro, incluidos los bordes, y no los de afuera', () {
      expect(area.contiene(const Coordenadas(lat: -34.5, lon: -56.5)), isTrue);
      expect(area.contiene(const Coordenadas(lat: -35, lon: -57)), isTrue);
      expect(area.contiene(const Coordenadas(lat: -33.9, lon: -56.5)), isFalse);
      expect(area.contiene(const Coordenadas(lat: -34.5, lon: -55.9)), isFalse);
    });

    test('cruzando el antimeridiano contiene ambos lados', () {
      const a = AreaMapa(sur: -10, oeste: 170, norte: 10, este: -170);
      expect(a.cruzaAntimeridiano, isTrue);
      expect(a.contiene(const Coordenadas(lat: 0, lon: 175)), isTrue);
      expect(a.contiene(const Coordenadas(lat: 0, lon: -175)), isTrue);
      expect(a.contiene(const Coordenadas(lat: 0, lon: 0)), isFalse);
    });

    test('un área no válida no contiene nada', () {
      for (final a in const [
        AreaMapa(sur: 1, oeste: 0, norte: 0, este: 1),
        AreaMapa(sur: -91, oeste: 0, norte: 0, este: 1),
        AreaMapa(sur: 0, oeste: -181, norte: 1, este: 1),
        AreaMapa(sur: double.nan, oeste: 0, norte: 1, este: 1),
      ]) {
        expect(a.esValida, isFalse, reason: '$a');
        expect(a.contiene(const Coordenadas(lat: 0.5, lon: 0.5)), isFalse, reason: '$a');
      }
    });
  });

  group('AgrupadorMarcadores', () {
    test('sin marcadores no hay grupos', () {
      expect(AgrupadorMarcadores.agrupar(const [], zoom: 10), isEmpty);
    });

    test('a zoom alto, marcadores separados quedan individuales', () {
      final grupos = AgrupadorMarcadores.agrupar([
        m('a', -34.9, -56.15),
        m('b', -34.91, -56.16),
      ], zoom: 18);
      expect(grupos, hasLength(2));
      expect(grupos.every((g) => g.esIndividual), isTrue);
    });

    test('a zoom bajo, marcadores cercanos se agrupan con el centro promedio y en orden de id', () {
      final grupos = AgrupadorMarcadores.agrupar([
        m('b', -34.9010, -56.1500),
        m('a', -34.9000, -56.1510),
      ], zoom: 10);
      expect(grupos, hasLength(1));
      final g = grupos.single;
      expect(g.cantidad, 2);
      expect(g.esIndividual, isFalse);
      expect([for (final x in g.marcadores) x.ubicacionId], ['a', 'b']);
      expect(g.centro.lat, closeTo(-34.9005, 1e-9));
      expect(g.centro.lon, closeTo(-56.1505, 1e-9));
    });

    test('es determinista y no pierde marcadores', () {
      final entrada = [
        for (var i = 0; i < 300; i++)
          m('u$i', -34.9 + (i % 20) * 0.001, -56.15 + (i ~/ 20) * 0.001),
      ];
      final a = AgrupadorMarcadores.agrupar(entrada, zoom: 13);
      final b = AgrupadorMarcadores.agrupar(entrada.reversed, zoom: 13);
      expect(a, b);
      expect(a.fold<int>(0, (s, g) => s + g.cantidad), 300);
      expect(a.length, lessThan(300));
    });

    test('menos grupos cuanto menor el zoom', () {
      final entrada = [for (var i = 0; i < 50; i++) m('u$i', -34.9 + i * 0.002, -56.15)];
      final lejos = AgrupadorMarcadores.agrupar(entrada, zoom: 8).length;
      final cerca = AgrupadorMarcadores.agrupar(entrada, zoom: 16).length;
      expect(lejos, lessThan(cerca));
    });

    test('zoom NaN o fuera de rango y radio inválido no rompen', () {
      final entrada = [m('a', -34.9, -56.15)];
      expect(AgrupadorMarcadores.agrupar(entrada, zoom: double.nan), hasLength(1));
      expect(AgrupadorMarcadores.agrupar(entrada, zoom: 99), hasLength(1));
      expect(AgrupadorMarcadores.agrupar(entrada, zoom: -3, radioPx: -1), hasLength(1));
    });
  });

  group('ResolutorFuenteTiles', () {
    test('paquete offline manda, haya red o no', () {
      for (final red in [true, false]) {
        expect(
          ResolutorFuenteTiles.resolver(hayPaqueteOffline: true, hayRed: red),
          FuenteTiles.pmtilesOffline,
        );
      }
    });

    test('sin paquete pero con red: servidor online', () {
      expect(
        ResolutorFuenteTiles.resolver(hayPaqueteOffline: false, hayRed: true),
        FuenteTiles.servidorOnline,
      );
    });

    test('sin paquete ni red: sin tiles', () {
      expect(
        ResolutorFuenteTiles.resolver(hayPaqueteOffline: false, hayRed: false),
        FuenteTiles.sinTiles,
      );
    });

    test('sin paquete y con el servidor rechazando (rate limit): sin tiles aunque haya red', () {
      expect(
        ResolutorFuenteTiles.resolver(
          hayPaqueteOffline: false,
          hayRed: true,
          servidorOnlineDisponible: false,
        ),
        FuenteTiles.sinTiles,
      );
    });
  });

  group('ResolutorCentroMapa', () {
    const gps = Coordenadas(lat: -34.9, lon: -56.15);
    const ultima = Coordenadas(lat: -31.4, lon: -58.0);
    const propia = Coordenadas(lat: -32.3, lon: -58.1);

    test('con GPS válido centra en el GPS y habilita "Mi ubicación"', () {
      final c = ResolutorCentroMapa.resolver(
        gps: gps,
        centroUltimaCiudad: ultima,
        centroCiudadColportor: propia,
      )!;
      expect(c.origen, OrigenCentroMapa.gps);
      expect(c.coordenadas, gps);
      expect(c.hayGps, isTrue);
    });

    test('sin GPS: última ciudad usada, y "Mi ubicación" deshabilitado', () {
      final c = ResolutorCentroMapa.resolver(
        centroUltimaCiudad: ultima,
        centroCiudadColportor: propia,
      )!;
      expect(c.origen, OrigenCentroMapa.ultimaCiudad);
      expect(c.coordenadas, ultima);
      expect(c.hayGps, isFalse);
    });

    test('sin GPS ni última ciudad: la ciudad del colportor', () {
      final c = ResolutorCentroMapa.resolver(centroCiudadColportor: propia)!;
      expect(c.origen, OrigenCentroMapa.ciudadColportor);
    });

    test('GPS en (0, 0), fuera de rango o NaN cuenta como sin GPS', () {
      for (final malo in const [
        Coordenadas(lat: 0, lon: 0),
        Coordenadas(lat: 95, lon: 0),
        Coordenadas(lat: double.nan, lon: 1),
        Coordenadas(lat: 1, lon: double.nan),
      ]) {
        final c = ResolutorCentroMapa.resolver(gps: malo, centroUltimaCiudad: ultima)!;
        expect(c.origen, OrigenCentroMapa.ultimaCiudad, reason: '$malo');
        expect(c.hayGps, isFalse);
      }
    });

    test('centros de ciudad inválidos se saltean; sin nada válido devuelve null', () {
      const invalido = Coordenadas(lat: 200, lon: 0);
      expect(
        ResolutorCentroMapa.resolver(
          centroUltimaCiudad: invalido,
          centroCiudadColportor: propia,
        )!.origen,
        OrigenCentroMapa.ciudadColportor,
      );
      expect(
        ResolutorCentroMapa.resolver(centroUltimaCiudad: invalido, centroCiudadColportor: invalido),
        isNull,
      );
      expect(ResolutorCentroMapa.resolver(), isNull);
    });
  });
}

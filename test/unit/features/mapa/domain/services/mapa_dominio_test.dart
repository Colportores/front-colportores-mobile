// Test de dominio: Dart puro (HU-UBI-003): área, fuente de tiles y centro del mapa.
import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:test/test.dart';

void main() {
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

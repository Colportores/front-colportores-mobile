// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:test/test.dart';

void main() {
  const italia = Coordenadas(lat: -34.891, lon: -56.125);

  group('Coordenadas', () {
    test(
      'dado un punto de Montevideo, cuando se consulta el rango, está en rango y no es cero',
      () {
        expect(italia.estanEnRango, isTrue);
        expect(italia.sonCero, isFalse);
      },
    );

    test('dado (0, 0), cuando se consulta, son cero', () {
      expect(const Coordenadas(lat: 0, lon: 0).sonCero, isTrue);
    });

    for (final (lat, lon) in [(-90.1, 0.0), (90.1, 0.0), (0.0, -180.1), (0.0, 180.1)]) {
      test('dado ($lat, $lon), cuando se consulta el rango, está fuera', () {
        expect(Coordenadas(lat: lat, lon: lon).estanEnRango, isFalse);
      });
    }

    test('dado dos puntos a 15 m hacia el norte, cuando se mide la distancia, da 15 m', () {
      const norte = Coordenadas(lat: -34.891 + 15 / 111195.08, lon: -56.125);

      expect(italia.distanciaMetrosA(norte), closeTo(15, 0.05));
    });

    test('dado el mismo punto, cuando se mide la distancia, da 0', () {
      expect(italia.distanciaMetrosA(italia), 0);
    });

    test('dado Montevideo y Buenos Aires, cuando se mide la distancia, da unos 208 km', () {
      const buenosAires = Coordenadas(lat: -34.6037, lon: -58.3816);

      expect(italia.distanciaMetrosA(buenosAires) / 1000, closeTo(208.6, 1));
    });
  });

  group('PuntoCapturado', () {
    test(
      'dado una lectura de GPS a 50 m, cuando se consulta, no es impreciso (el umbral es > 50)',
      () {
        final punto = PuntoCapturado.gps(
          const LecturaGps(coordenadas: italia, precisionMetros: 50),
        );

        expect(punto.esImpreciso, isFalse);
        expect(punto.origen, OrigenCoordenadas.gps);
        expect(punto.precisionMetros, 50);
      },
    );

    test('dado una lectura de GPS a 50,5 m, cuando se consulta, es impreciso', () {
      final punto = PuntoCapturado.gps(
        const LecturaGps(coordenadas: italia, precisionMetros: 50.5),
      );

      expect(punto.esImpreciso, isTrue);
    });

    for (final precision in [double.nan, -1.0, double.infinity]) {
      test('dado una lectura de GPS con precisión $precision, cuando se consulta, cuenta como '
          'imprecisa', () {
        final punto = PuntoCapturado.gps(
          LecturaGps(coordenadas: italia, precisionMetros: precision),
        );

        expect(punto.esImpreciso, isTrue);
      });
    }

    test('dado un marcador manual, cuando se consulta, no tiene precisión ni es impreciso', () {
      const punto = PuntoCapturado.manual(italia);

      expect(punto.origen, OrigenCoordenadas.manual);
      expect(punto.precisionMetros, isNull);
      expect(punto.esImpreciso, isFalse);
    });
  });
}

// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Ubicacion construir({
    TipoUbicacion tipo = TipoUbicacion.casa,
    double lat = -34.9,
    double lon = -56.1,
  }) => Ubicacion(
    id: 'ub-1',
    tipo: tipo,
    calle: 'Av. Italia',
    numero: '1234',
    lat: lat,
    lon: lon,
    ciudadId: 'ciudad-1',
    zonaId: 'zona-1',
    auditoria: auditoria,
  );

  group('Ubicacion', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir();
      final b = construir();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que tipo difiere, cuando se comparan, no son iguales', () {
      final a = construir(tipo: TipoUbicacion.casa);
      final b = construir(tipo: TipoUbicacion.edificio);

      expect(a, isNot(equals(b)));
    });

    test('dado que lat/lon difieren, cuando se comparan, no son iguales', () {
      final a = construir(lat: -34.9, lon: -56.1);
      final b = construir(lat: -34.8, lon: -56.0);

      expect(a, isNot(equals(b)));
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final ubicacion = Ubicacion(
        id: 'ub-1',
        tipo: TipoUbicacion.casa,
        calle: 'Av. Italia',
        numero: '1234',
        lat: -34.9,
        lon: -56.1,
        ciudadId: 'ciudad-1',
        zonaId: 'zona-1',
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(ubicacion.estaBorrada, isTrue);
    });

    test('dado un alta por marcador manual sin dirección ni zona, cuando se construye, calle, '
        'número y zona quedan en null', () {
      final ubicacion = Ubicacion(
        id: 'ub-2',
        tipo: TipoUbicacion.negocio,
        lat: -34.9,
        lon: -56.1,
        ciudadId: 'ciudad-1',
        auditoria: auditoria,
      );

      expect((ubicacion.calle, ubicacion.numero, ubicacion.zonaId), (null, null, null));
      expect(ubicacion.coordenadas, const Coordenadas(lat: -34.9, lon: -56.1));
    });
  });

  group('TipoUbicacion.reduceAUnEspacioHacia (S17)', () {
    test('dado un cambio de tipo, cuando se pregunta si deja un solo espacio, solo EDIFICIO a '
        'CASA o NEGOCIO y NEGOCIO a CASA lo hacen', () {
      final reducen = {
        (TipoUbicacion.edificio, TipoUbicacion.casa),
        (TipoUbicacion.edificio, TipoUbicacion.negocio),
        (TipoUbicacion.negocio, TipoUbicacion.casa),
      };

      for (final de in TipoUbicacion.values) {
        for (final a in TipoUbicacion.values) {
          expect(de.reduceAUnEspacioHacia(a), reducen.contains((de, a)), reason: '$de -> $a');
        }
      }
    });
  });

  group('FailureUbicacionConEspacios', () {
    test(
      'dado una cuenta de 0 o 1 espacios, cuando se construye, falla: el aviso es solo plural',
      () {
        for (final cantidad in [0, 1]) {
          expect(
            () => FailureUbicacionConEspacios(cantidadEspacios: cantidad),
            throwsA(isA<AssertionError>()),
            reason: '$cantidad',
          );
        }
      },
    );

    test('dado una cuenta de 2 o más espacios, cuando se construye, dice el texto literal', () {
      expect(
        const FailureUbicacionConEspacios(cantidadEspacios: 2).mensaje,
        'Esta ubicación tiene 2 espacios. Borralos o reubicalos primero.',
      );
    });
  });
}

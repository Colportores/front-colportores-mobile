// Test de dominio: Dart puro (ResolutorSituacionMapa).
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:test/test.dart';

PaqueteTiles _paquete({int bytes = 44200000, bool enPartes = false}) => PaqueteTiles(
  id: 'ciudad-montevideo',
  nivel: NivelCobertura.ciudad,
  ambitoId: 'c-1',
  version: 'v1',
  partes: [
    ParteTiles(
      origen: Uri.parse('https://tiles.test/ciudad-montevideo-p1.pmtiles'),
      tamanoBytes: enPartes ? bytes ~/ 2 : bytes,
      sha256: 'a' * 64,
    ),
    if (enPartes)
      ParteTiles(
        origen: Uri.parse('https://tiles.test/ciudad-montevideo-p2.pmtiles'),
        tamanoBytes: bytes ~/ 2,
        sha256: 'b' * 64,
      ),
  ],
);

const _descargado = ['/tiles/ciudad-montevideo-p1-aaaaaaaaaaaa.pmtiles'];

void main() {
  SituacionMapa resolver({
    TipoConexion? conexion,
    List<String>? rutas = const [],
    PaqueteDelAmbito? consulta,
  }) => ResolutorSituacionMapa.resolver(
    conexion: conexion,
    rutasDescargadas: rutas,
    consulta: consulta,
  );

  group('con el mapa de la ciudad descargado', () {
    for (final conexion in [...TipoConexion.values, null]) {
      test(
        '${conexion?.name ?? 'sin saber la conexión'}: el mapa sale del paquete y no hay aviso',
        () {
          final situacion = resolver(
            conexion: conexion,
            rutas: _descargado,
            consulta: const PaqueteSinRed(),
          );

          expect(situacion.fuente.tipo, FuenteTiles.pmtilesOffline);
          expect(situacion.fuente.origenes, _descargado);
          expect(situacion.aviso, isNull);
        },
      );
    }

    test('el paquete descargado manda aunque el catálogo traiga otro y haya datos móviles', () {
      final situacion = resolver(
        conexion: TipoConexion.datosMoviles,
        rutas: _descargado,
        consulta: PaqueteHallado(_paquete()),
      );

      expect(situacion.fuente.tipo, FuenteTiles.pmtilesOffline);
      expect(situacion.aviso, isNull);
    });
  });

  group('06C·05 / 06C·06 · sin conexión y sin el mapa descargado', () {
    test('color liso y aviso de sin conexión', () {
      final situacion = resolver(conexion: TipoConexion.sinConexion);

      expect(situacion.fuente.hayTiles, isFalse);
      expect(situacion.aviso, const AvisoSinConexion());
    });

    test('lo dice aunque no se sepa el ámbito o el catálogo (no hace falta para saberlo)', () {
      for (final consulta in <PaqueteDelAmbito?>[
        null,
        const PaqueteSinAmbito(),
        const PaqueteSinRed(),
        const PaqueteNoDisponible(),
      ]) {
        expect(
          resolver(conexion: TipoConexion.sinConexion, consulta: consulta).aviso,
          const AvisoSinConexion(),
          reason: '$consulta',
        );
      }
    });
  });

  group('06C·07 · con datos móviles y sin el mapa descargado', () {
    test('el mapa en línea del catálogo y el aviso con el peso del paquete', () {
      final paquete = _paquete();
      final situacion = resolver(
        conexion: TipoConexion.datosMoviles,
        consulta: PaqueteHallado(paquete),
      );

      expect(situacion.fuente.tipo, FuenteTiles.servidorOnline);
      expect(situacion.fuente.origenes, ['https://tiles.test/ciudad-montevideo-p1.pmtiles']);
      expect(situacion.aviso, AvisoDatosMoviles(paquete));
      expect((situacion.aviso! as AvisoDatosMoviles).megabytes, 45);
    });

    test('un paquete en dos partes usa una URL por parte y suma los MB', () {
      final paquete = _paquete(bytes: 88400000, enPartes: true);
      final situacion = resolver(
        conexion: TipoConexion.datosMoviles,
        consulta: PaqueteHallado(paquete),
      );

      expect(situacion.fuente.origenes, [
        'https://tiles.test/ciudad-montevideo-p1.pmtiles',
        'https://tiles.test/ciudad-montevideo-p2.pmtiles',
      ]);
      expect((situacion.aviso! as AvisoDatosMoviles).megabytes, 89);
    });
  });

  group('con Wi-Fi y sin el mapa descargado', () {
    test('el mapa en línea y ningún aviso', () {
      final situacion = resolver(conexion: TipoConexion.wifi, consulta: PaqueteHallado(_paquete()));

      expect(situacion.fuente.tipo, FuenteTiles.servidorOnline);
      expect(situacion.aviso, isNull);
    });
  });

  group('«No pudimos cargar el mapa de esta ciudad»', () {
    for (final conexion in [TipoConexion.wifi, TipoConexion.datosMoviles]) {
      test(
        'con ${conexion.name} y el catálogo sin paquete: color liso (sin grises) y el aviso',
        () {
          final situacion = resolver(conexion: conexion, consulta: const PaqueteNoDisponible());

          expect(situacion.fuente, const FuenteMapa.sinTiles());
          expect(situacion.aviso, const AvisoMapaNoCarga());
        },
      );
    }
  });

  group('sin saber todavía: no se afirma nada', () {
    test('no se sabe lo descargado: color liso y ningún aviso, ni «Sin conexión»', () {
      final situacion = resolver(conexion: TipoConexion.sinConexion, rutas: null);

      expect(situacion, const SituacionMapa.sinDatos());
      expect(situacion.aviso, isNull);
    });

    test('no se sabe la conexión: ningún aviso', () {
      expect(resolver(consulta: const PaqueteNoDisponible()), const SituacionMapa.sinDatos());
    });

    test('con conexión pero sin respuesta del catálogo todavía: ningún aviso', () {
      expect(resolver(conexion: TipoConexion.wifi), const SituacionMapa.sinDatos());
    });

    for (final consulta in [const PaqueteSinAmbito(), const PaqueteSinRed()]) {
      test('con conexión y ${consulta.runtimeType}: ningún aviso', () {
        for (final conexion in [TipoConexion.wifi, TipoConexion.datosMoviles]) {
          expect(
            resolver(conexion: conexion, consulta: consulta),
            const SituacionMapa.sinDatos(),
            reason: conexion.name,
          );
        }
      });
    }
  });

  test('los avisos y las consultas se comparan por valor', () {
    final paquete = _paquete();
    expect(const AvisoSinConexion(), const AvisoSinConexion());
    expect(const AvisoMapaNoCarga(), isNot(const AvisoSinConexion()));
    expect(AvisoDatosMoviles(paquete), AvisoDatosMoviles(paquete));
    expect(PaqueteHallado(paquete), PaqueteHallado(paquete));
    expect(const PaqueteSinRed(), const PaqueteSinRed());
    expect(const PaqueteNoDisponible(), isNot(const PaqueteSinAmbito()));
    expect(const SituacionMapa.sinDatos(), const SituacionMapa(fuente: FuenteMapa.sinTiles()));
  });
}

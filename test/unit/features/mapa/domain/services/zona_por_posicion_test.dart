// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/zona_ubicable.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ubicador_zona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/zona_por_posicion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/zonas_falsas.dart';

void main() {
  const regla = ZonaPorPosicion();

  // Dos zonas vecinas que comparten la calle lon = -56.15 como borde.
  ZonaUbicable oeste(String id, {String campaniaId = 'camp-1', String ciudadId = 'mvd'}) =>
      zonaRectangular(
        id,
        campaniaId: campaniaId,
        ciudadId: ciudadId,
        latSur: -34.95,
        latNorte: -34.85,
        lonOeste: -56.2,
        lonEste: -56.15,
      );
  ZonaUbicable este(String id, {String campaniaId = 'camp-1'}) => zonaRectangular(
    id,
    campaniaId: campaniaId,
    latSur: -34.95,
    latNorte: -34.85,
    lonOeste: -56.15,
    lonEste: -56.1,
  );

  const enOeste = Coordenadas(lat: -34.9, lon: -56.18);
  const enLaCalle = Coordenadas(lat: -34.9, lon: -56.15);
  const lejos = Coordenadas(lat: -34.7, lon: -55.9);

  String? zonaDe(
    Coordenadas punto,
    List<ZonaUbicable> zonas, {
    Set<String> vigentes = const {'camp-1', 'camp-2'},
    List<String> preferidas = const ['camp-1'],
  }) => regla.zonaDe(
    punto,
    ciudadId: 'mvd',
    zonas: zonas,
    campaniasVigentes: vigentes,
    campaniasPreferidas: preferidas,
  );

  group('ZonaPorPosicion', () {
    test('dado un punto dentro de una zona, devuelve esa zona', () {
      expect(zonaDe(enOeste, [oeste('z-oeste'), este('z-este')]), 'z-oeste');
    });

    test('dado un punto fuera de toda zona, devuelve null', () {
      expect(zonaDe(lejos, [oeste('z-oeste'), este('z-este')]), isNull);
      expect(zonaDe(enOeste, const []), isNull);
    });

    test('dado un punto sobre el borde que comparten dos zonas de la misma campaña, queda en la '
        'de menor id', () {
      expect(zonaDe(enLaCalle, [este('0192-a'), oeste('0192-b')]), '0192-a');
      expect(zonaDe(enLaCalle, [oeste('0192-b'), este('0192-a')]), '0192-a');
    });

    test('compara los id en minúsculas, como el uuid de Postgres', () {
      expect(zonaDe(enLaCalle, [oeste('0192-B'), este('0192-c')]), '0192-B');
      expect(zonaDe(enLaCalle, [oeste('0192-b'), este('0192-C')]), '0192-b');
    });

    test('dado el borde entre zonas de dos campañas, gana la de la campaña preferida aunque '
        'tenga mayor id (D2)', () {
      final zonas = [oeste('0192-a', campaniaId: 'camp-2'), este('0192-z', campaniaId: 'camp-1')];

      expect(zonaDe(enLaCalle, zonas, preferidas: ['camp-1']), '0192-z');
      expect(zonaDe(enLaCalle, zonas, preferidas: ['camp-2', 'camp-1']), '0192-a');
      expect(zonaDe(enLaCalle, zonas, preferidas: const []), '0192-a');
    });

    test('la campaña preferida se compara en minúsculas', () {
      final zonas = [oeste('0192-a', campaniaId: 'camp-2'), este('0192-z', campaniaId: 'CAMP-1')];

      expect(zonaDe(enLaCalle, zonas, vigentes: {'camp-2', 'CAMP-1'}), '0192-z');
    });

    test('ignora las zonas de campañas que no están vigentes', () {
      final zonas = [oeste('z-vieja', campaniaId: 'camp-vieja')];

      expect(zonaDe(enOeste, zonas), isNull);
      expect(zonaDe(enOeste, zonas, vigentes: {'camp-vieja'}), 'z-vieja');
    });

    test('ignora las zonas de otra ciudad aunque cubran el punto', () {
      expect(zonaDe(enOeste, [oeste('z-otra', ciudadId: 'canelones')]), isNull);
    });
  });

  group('UbicadorZona', () {
    late ZonasEnMemoria zonas;
    late InscripcionesEnMemoria inscripciones;
    late UbicadorZona ubicador;

    setUp(() {
      zonas = ZonasEnMemoria();
      inscripciones = InscripcionesEnMemoria();
      ubicador = UbicadorZona(zonas, inscripciones);
    });

    Future<Either<Failure, ZonaDelPunto>> ubicar(Coordenadas punto, {String ciudadId = 'mvd'}) =>
        ubicador.ubicar(punto, colportorId: 'col-1', ciudadId: ciudadId);

    test(
      'dado un punto en la zona asignada al colportor, la devuelve como una de las suyas',
      () async {
        zonas.zonas.addAll([oeste('z-oeste'), este('z-este')]);
        inscripciones.inscripciones.add(inscripcion('col-1', 'camp-1', zonaId: 'z-oeste'));

        expect(
          await ubicar(enOeste),
          const Right<Failure, ZonaDelPunto>((zonaId: 'z-oeste', esDeMisZonas: true)),
        );
      },
    );

    test('dado un punto en otra zona de su campaña, la devuelve pero no como suya', () async {
      zonas.zonas.addAll([oeste('z-oeste'), este('z-este')]);
      inscripciones.inscripciones.add(inscripcion('col-1', 'camp-1', zonaId: 'z-este'));

      expect(
        await ubicar(enOeste),
        const Right<Failure, ZonaDelPunto>((zonaId: 'z-oeste', esDeMisZonas: false)),
      );
    });

    test('dado un colportor sin zona asignada, ubica el punto igual', () async {
      zonas.zonas.add(oeste('z-oeste'));
      inscripciones.inscripciones.add(inscripcion('col-1', 'camp-1'));

      expect(
        await ubicar(enOeste),
        const Right<Failure, ZonaDelPunto>((zonaId: 'z-oeste', esDeMisZonas: false)),
      );
    });

    test('dado un punto fuera de toda zona, zona null y no es de las suyas', () async {
      zonas.zonas.add(oeste('z-oeste'));
      inscripciones.inscripciones.add(inscripcion('col-1', 'camp-1', zonaId: 'z-oeste'));

      expect(
        await ubicar(lejos),
        const Right<Failure, ZonaDelPunto>((zonaId: null, esDeMisZonas: false)),
      );
    });

    test(
      'dado un colportor sin inscripciones vigentes, ninguna zona cuenta como vigente',
      () async {
        zonas.zonas.add(oeste('z-oeste'));
        inscripciones.inscripciones.add(inscripcion('col-2', 'camp-1', zonaId: 'z-oeste'));

        expect(
          await ubicar(enOeste),
          const Right<Failure, ZonaDelPunto>((zonaId: null, esDeMisZonas: false)),
        );
      },
    );

    test('con dos campañas vigentes, prefiere la de menor id (D2 provisoria)', () async {
      zonas.zonas.addAll([
        oeste('0192-a', campaniaId: 'camp-b'),
        este('0192-z', campaniaId: 'camp-a'),
      ]);
      inscripciones.inscripciones.addAll([
        inscripcion('col-1', 'camp-b'),
        inscripcion('col-1', 'camp-a', zonaId: '0192-z'),
      ]);

      expect(
        await ubicar(enLaCalle),
        const Right<Failure, ZonaDelPunto>((zonaId: '0192-z', esDeMisZonas: true)),
      );
    });

    test('solo mira las zonas de la ciudad del punto', () async {
      zonas.zonas.add(oeste('z-oeste'));
      inscripciones.inscripciones.add(inscripcion('col-1', 'camp-1', zonaId: 'z-oeste'));

      expect(
        await ubicar(enOeste, ciudadId: 'canelones'),
        const Right<Failure, ZonaDelPunto>((zonaId: null, esDeMisZonas: false)),
      );
    });

    test('si no se pueden leer las inscripciones o las zonas, devuelve esa falla', () async {
      inscripciones.falla = const FailureInesperado();
      expect(await ubicar(enOeste), const Left<Failure, ZonaDelPunto>(FailureInesperado()));

      inscripciones.falla = null;
      zonas.falla = const FailureDatosLocalesIlegibles();
      expect(
        await ubicar(enOeste),
        const Left<Failure, ZonaDelPunto>(FailureDatosLocalesIlegibles()),
      );
    });
  });
}

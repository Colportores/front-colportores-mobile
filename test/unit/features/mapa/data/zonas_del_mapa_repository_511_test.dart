// Las zonas del mapa de ubicaciones leídas de las réplicas locales del pull (HU-UBI-003, #511): sin
// red, con las filas entrando por el mismo `DriftLocalStore` del pull de catálogos.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/zonas_del_mapa_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/zona_del_mapa.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/replica_de_campanias.dart';

const _usuario = 'col-1';

Map<String, Object?> _zona(
  String id,
  String nombre, {
  String cc = 'cc-mvd',
  double lonOeste = -56.20,
  String? color = '#336699',
  bool deBaja = false,
}) => filaZona(
  id,
  nombre,
  campaniaCiudad: cc,
  latSur: -34.92,
  latNorte: -34.88,
  lonOeste: lonOeste,
  lonEste: lonOeste + .05,
  color: color,
  deBaja: deBaja,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;
  late ZonasDelMapaRepositoryImpl repo;
  var hoy = DateTime.utc(2026, 10, 27, 15);

  setUp(() {
    hoy = DateTime.utc(2026, 10, 27, 15);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
    repo = ZonasDelMapaRepositoryImpl(db, ahora: () => hoy);
  });
  tearDown(() => db.close());

  Future<void> asentar() => pumpEventQueue(times: 100);

  Future<List<List<ZonaDelMapa>>> escuchar({String usuario = _usuario}) async {
    final emisiones = <List<ZonaDelMapa>>[];
    final suscripcion = repo.observar(usuario).listen(emisiones.add);
    addTearDown(suscripcion.cancel);
    await asentar();
    return emisiones;
  }

  /// La campaña `camp-1` en Montevideo con las zonas [zonas], y [zonaPropia] asignada a `col-1`.
  Future<void> sembrar(List<Map<String, Object?>> zonas, {String? zonaPropia}) => replica.bajar({
    'campania': [filaCampania('camp-1', 'Verano 2026')],
    'campania_ciudad': [filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd')],
    'zona': zonas,
    'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: zonaPropia)],
  });

  List<String> ids(List<ZonaDelMapa> zonas) => [for (final z in zonas) z.id];

  group('qué zonas hay', () {
    test('las de la campaña del colportor, con la propia marcada', () async {
      await sembrar([
        _zona('z-a', 'Centro'),
        _zona('z-b', 'Cordón', lonOeste: -56.15),
      ], zonaPropia: 'z-b');

      final emisiones = await escuchar();

      expect(emisiones, hasLength(1));
      final zonas = emisiones.single;
      expect(ids(zonas), ['z-a', 'z-b']);
      expect([for (final z in zonas) z.propia], [false, true]);
      expect(zonas.first.nombre, 'Centro');
      expect(zonas.first.color, '#336699');
    });

    test('sin zona asignada ninguna es propia: se ven todas como las demás', () async {
      await sembrar([_zona('z-a', 'Centro'), _zona('z-b', 'Cordón', lonOeste: -56.15)]);

      final zonas = (await escuchar()).single;

      expect(zonas, hasLength(2));
      expect(zonas.any((z) => z.propia), isFalse);
    });

    test('una zona sin color queda con color nulo (el mapa pone el de siempre)', () async {
      await sembrar([_zona('z-a', 'Centro', color: null)]);

      expect((await escuchar()).single.single.color, isNull);
    });

    test('sin ninguna fila replicada emite la lista vacía', () async {
      expect(await escuchar(), [isEmpty]);
    });

    test('sin base abierta emite la lista vacía', () async {
      final sinBase = ZonasDelMapaRepositoryImpl(null);

      expect(await sinBase.observar(_usuario).toList(), [isEmpty]);
    });

    test('la propia dentro de otra: las dos salen, cada una con lo suyo', () async {
      final grande = _zona('z-grande', 'Ciudad vieja');
      final chica = filaZona(
        'z-chica',
        'Plaza',
        campaniaCiudad: 'cc-mvd',
        latSur: -34.91,
        latNorte: -34.90,
        lonOeste: -56.19,
        lonEste: -56.18,
      );
      await sembrar([grande, chica], zonaPropia: 'z-chica');

      final zonas = (await escuchar()).single;

      expect({for (final z in zonas) z.id: z.propia}, {'z-grande': false, 'z-chica': true});
    });

    test('muchas zonas: las 300 salen ordenadas por id', () async {
      final filas = [
        for (var i = 0; i < 300; i++)
          _zona('z-${i.toString().padLeft(3, '0')}', 'Zona $i', lonOeste: -56.5 + i * .001),
      ];
      await sembrar(filas, zonaPropia: 'z-150');

      final zonas = (await escuchar()).single;

      expect(zonas, hasLength(300));
      expect(ids(zonas), [...ids(zonas)]..sort());
      expect(zonas.where((z) => z.propia).single.id, 'z-150');
    });
  });

  group('qué zonas no', () {
    test('las de otra campaña en la que el colportor no está inscripto', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026'), filaCampania('camp-2', 'Otra')],
        'campania_ciudad': [
          filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
          filaCampaniaCiudad('cc-otra', campania: 'camp-2', ciudad: 'ciu-mvd'),
        ],
        'zona': [_zona('z-a', 'Centro'), _zona('z-x', 'Ajena', cc: 'cc-otra')],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });

      expect(ids((await escuchar()).single), ['z-a']);
    });

    test('las de otro colportor', () async {
      await sembrar([_zona('z-a', 'Centro')]);

      expect(await escuchar(usuario: 'col-2'), [isEmpty]);
    });

    test('con la inscripción dada de baja no queda ninguna', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026')],
        'campania_ciudad': [filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd')],
        'zona': [_zona('z-a', 'Centro')],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', deBaja: true)],
      });

      expect(await escuchar(), [isEmpty]);
    });

    test('una zona dada de baja, o con su campania_ciudad de baja, no se dibuja', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026')],
        'campania_ciudad': [
          filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
          filaCampaniaCiudad('cc-baja', campania: 'camp-1', ciudad: 'ciu-lp', deBaja: true),
        ],
        'zona': [
          _zona('z-a', 'Centro'),
          _zona('z-baja', 'Vieja', deBaja: true),
          _zona('z-cc-baja', 'Las Piedras', cc: 'cc-baja'),
        ],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });

      expect(ids((await escuchar()).single), ['z-a']);
    });

    test('las de una campaña terminada o dada de baja; sin fecha de fin sí', () async {
      await replica.bajar({
        'campania': [
          filaCampania('camp-1', 'Terminada', fin: '2026-10-26'),
          filaCampania('camp-2', 'Hoy', fin: '2026-10-27'),
          filaCampania('camp-3', 'Sin fin', fin: null),
          filaCampania('camp-4', 'Baja', deBaja: true),
        ],
        'campania_ciudad': [
          for (var i = 1; i <= 4; i++)
            filaCampaniaCiudad('cc-$i', campania: 'camp-$i', ciudad: 'ciu-$i'),
        ],
        'zona': [
          for (var i = 1; i <= 4; i++) _zona('z-$i', 'Z$i', cc: 'cc-$i', lonOeste: -56.2 + i * .1),
        ],
        'campania_colportor': [
          for (var i = 1; i <= 4; i++) filaInscripcion('insc-$i', campania: 'camp-$i'),
        ],
      });

      expect(ids((await escuchar()).single), ['z-2', 'z-3']);
    });

    test('una forma rota se saltea y no esconde a las demás', () async {
      await sembrar([
        _zona('z-a', 'Centro'),
        {
          ..._zona('z-rota', 'Rota'),
          'poligono_geojson': {
            'type': 'Polygon',
            'coordinates': [
              [
                [-56.2, -34.9],
              ],
            ],
          },
        },
        _zona('z-b', 'Cordón', lonOeste: -56.15),
      ]);

      expect(ids((await escuchar()).single), ['z-a', 'z-b']);
    });
  });

  group('al día con el pull', () {
    test(
      'un pull que suma, renombra, cambia la zona propia o da de baja vuelve a emitir',
      () async {
        await sembrar([_zona('z-a', 'Centro')]);
        final emisiones = <List<ZonaDelMapa>>[];
        final suscripcion = repo.observar(_usuario).listen(emisiones.add);
        addTearDown(suscripcion.cancel);
        await asentar();
        expect(emisiones.last.single.propia, isFalse);

        await replica.bajar({
          'zona': [_zona('z-a', 'Centro viejo'), _zona('z-b', 'Cordón', lonOeste: -56.15)],
          'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: 'z-a')],
        });
        await asentar();
        expect(ids(emisiones.last), ['z-a', 'z-b']);
        expect(emisiones.last.first.nombre, 'Centro viejo');
        expect(emisiones.last.first.propia, isTrue);

        await replica.bajar({
          'zona': [_zona('z-a', 'Centro viejo', deBaja: true)],
        });
        await asentar();
        expect(ids(emisiones.last), ['z-b']);
      },
    );

    test('el fin de la campaña se vuelve a mirar en cada emisión (la fecha de hoy)', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026', fin: '2026-10-27')],
        'campania_ciudad': [filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd')],
        'zona': [_zona('z-a', 'Centro')],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });
      final emisiones = <List<ZonaDelMapa>>[];
      final suscripcion = repo.observar(_usuario).listen(emisiones.add);
      addTearDown(suscripcion.cancel);
      await asentar();
      expect(emisiones.last, hasLength(1));

      hoy = DateTime.utc(2026, 10, 29, 15);
      await replica.bajar({
        'zona': [_zona('z-a', 'Centro otra vez')],
      });
      await asentar();

      expect(emisiones.last, isEmpty);
    });
  });
}

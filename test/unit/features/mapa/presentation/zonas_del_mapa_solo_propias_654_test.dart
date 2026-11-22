// HU-UBI-003 (#654, decisión de Cristian 04/11): el colportor ve en su mapa solo sus zonas dibujadas.
// Con la base local real (las filas entran por el mismo `DriftLocalStore` del pull de catálogos) se
// prueba lo que cambia y lo que no: la réplica y el repositorio siguen trayendo TODAS las zonas de
// la ciudad (el cálculo de la zona de cada punto las necesita); el dibujo y el lector de pantalla
// reciben solo las propias.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/zonas_del_mapa_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/zona_del_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/zonas_del_mapa_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/replica_de_campanias.dart';

Map<String, Object?> _zona(String id, String nombre, {double lonOeste = -56.20}) => filaZona(
  id,
  nombre,
  campaniaCiudad: 'cc-mvd',
  latSur: -34.92,
  latNorte: -34.88,
  lonOeste: lonOeste,
  lonEste: lonOeste + .05,
  color: '#336699',
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
  });
  tearDown(() => db.close());

  /// La campaña `camp-1` en Montevideo con tres zonas y las inscripciones de [inscripciones]
  /// (colportor → zona asignada, o `null` si no tiene).
  Future<void> sembrar(Map<String, String?> inscripciones) => replica.bajar({
    'campania': [filaCampania('camp-1', 'Verano 2026')],
    'campania_ciudad': [filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd')],
    'zona': [
      _zona('z-ana', 'Cerro Norte'),
      _zona('z-beto', 'La Teja', lonOeste: -56.14),
      _zona('z-caro', 'Belvedere', lonOeste: -56.08),
    ],
    'campania_colportor': [
      for (final (i, e) in inscripciones.entries.indexed)
        filaInscripcion('insc-$i', campania: 'camp-1', usuario: e.key, zona: e.value),
    ],
  });

  ProviderContainer contenedor() {
    final c = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWithValue(db),
        zonasDelMapaRepositoryProvider.overrideWithValue(ZonasDelMapaRepositoryImpl(db)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Lo último que emite `zonasDelMapaProvider(colportor)`, esperando a que haya una emisión.
  Future<List<ZonaDelMapa>> dibujadasPor(ProviderContainer c, String colportor) async {
    final suscripcion = c.listen(zonasDelMapaProvider(colportor), (_, _) {});
    addTearDown(suscripcion.close);
    return c.read(zonasDelMapaProvider(colportor).future);
  }

  group('qué dibuja el mapa de cada colportor', () {
    test('dos colportores en la misma campaña y ciudad: cada uno dibuja solo la suya', () async {
      await sembrar({'col-1': 'z-ana', 'col-2': 'z-beto'});
      final c = contenedor();

      final deAna = await dibujadasPor(c, 'col-1');
      final deBeto = await dibujadasPor(c, 'col-2');

      expect([for (final z in deAna) z.id], ['z-ana']);
      expect(deAna.single.propia, isTrue);
      expect([for (final z in deBeto) z.id], ['z-beto']);
    });

    test('sin zona asignada no dibuja ninguna, aunque la ciudad tenga zonas de otros', () async {
      await sembrar({'col-1': null, 'col-2': 'z-beto'});
      final c = contenedor();

      expect(await dibujadasPor(c, 'col-1'), isEmpty);
      expect(c.read(zonasParaElMapaProvider('col-1')).dibujo, isEmpty);
      expect(c.read(zonasParaElMapaProvider('col-1')).paraElLector, isNull);
    });

    test('lo que se dibuja y lo que oye el lector es solo la zona propia', () async {
      await sembrar({'col-1': 'z-ana', 'col-2': 'z-beto'});
      final c = contenedor();
      await dibujadasPor(c, 'col-1');

      final zonas = c.read(zonasParaElMapaProvider('col-1'));

      expect([for (final z in zonas.dibujo) z.id], ['z-ana']);
      expect(zonas.dibujo.single.rotulo, 'Tu zona · Cerro Norte');
      expect(zonas.paraElLector, 'Tu zona: Cerro Norte.');
    });

    test(
      'un pull que le asigna otra zona cambia el dibujo; uno que se la quita lo vacía',
      () async {
        await sembrar({'col-1': 'z-ana'});
        final c = contenedor();
        final emisiones = <List<String>>[];
        c.listen(
          zonasDelMapaProvider('col-1'),
          (_, nuevo) => emisiones.add([for (final z in nuevo.value ?? const <ZonaDelMapa>[]) z.id]),
          fireImmediately: true,
        );
        await pumpEventQueue(times: 100);
        expect(emisiones.last, ['z-ana']);

        await replica.bajar({
          'campania_colportor': [filaInscripcion('insc-0', campania: 'camp-1', zona: 'z-caro')],
        });
        await pumpEventQueue(times: 100);
        expect(emisiones.last, ['z-caro']);

        await replica.bajar({
          'campania_colportor': [filaInscripcion('insc-0', campania: 'camp-1')],
        });
        await pumpEventQueue(times: 100);
        expect(emisiones.last, isEmpty);
      },
    );
  });

  group('lo que NO cambia: la lectura completa para calcular la zona de cada punto', () {
    test(
      'el repositorio sigue trayendo todas las zonas de la ciudad, con la propia marcada',
      () async {
        await sembrar({'col-1': 'z-ana', 'col-2': 'z-beto'});

        final todas = await ZonasDelMapaRepositoryImpl(db).observar('col-1').first;

        expect([for (final z in todas) z.id], ['z-ana', 'z-beto', 'z-caro']);
        expect([for (final z in todas) z.propia], [true, false, false]);
      },
    );

    test(
      'las filas de las zonas ajenas siguen en la réplica local (sin cambios de esquema)',
      () async {
        await sembrar({'col-1': 'z-ana'});

        final ids = [for (final z in await db.select(db.zonas).get()) z.id];

        expect(ids, unorderedEquals(['z-ana', 'z-beto', 'z-caro']));
      },
    );
  });
}

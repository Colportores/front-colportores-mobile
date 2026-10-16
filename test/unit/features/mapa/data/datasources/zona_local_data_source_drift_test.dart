import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/zona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/models/campania_ciudad_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/zona_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/zona_vertice_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/zona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/zonas_falsas.dart';

/// Un data source que falla al leer.
final class _LocalQueFalla implements ZonaLocalDataSource {
  @override
  Future<List<ZonaDeCiudad>> vivasDeCiudad(String ciudadId) async => throw StateError('disco roto');
}

void main() {
  final t0 = DateTime.utc(2026, 9, 29, 22);
  final auditoria = Auditoria(createdAt: t0, updatedAt: t0);
  final baja = Auditoria(createdAt: t0, updatedAt: t0, deletedAt: t0);

  late AppDatabase db;
  late ZonaLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = ZonaLocalDataSourceDrift(db);
  });

  tearDown(() => db.close());

  Future<void> ciudadDeCampania(
    String id,
    String campaniaId,
    String ciudadId, {
    bool deBaja = false,
  }) => db
      .into(db.campaniasCiudad)
      .insert(
        CampaniaCiudadModel(
          id: id,
          campaniaId: campaniaId,
          ciudadId: ciudadId,
          auditoria: deBaja ? baja : auditoria,
        ).aFila(),
      );

  ZonaModel zona(
    String id,
    String campaniaCiudadId, {
    bool deBaja = false,
    Map<String, Object?>? forma,
  }) => ZonaModel(
    id: id,
    nombre: 'Zona $id',
    campaniaCiudadId: campaniaCiudadId,
    tipoForma: 'ESQUINAS',
    poligonoGeojson:
        forma ??
        rectanguloGeojson(latSur: -34.95, latNorte: -34.85, lonOeste: -56.2, lonEste: -56.1),
    color: '#AABBCC',
    auditoria: deBaja ? baja : auditoria,
  );

  Future<void> guardar(ZonaModel z) => db.into(db.zonas).insert(z.aFila());

  group('ZonaLocalDataSourceDrift.vivasDeCiudad', () {
    test('devuelve las zonas vivas de la ciudad con su campaña, ordenadas por id, y la forma tal '
        'como se guardó', () async {
      await ciudadDeCampania('cc-mvd-1', 'camp-1', 'mvd');
      await ciudadDeCampania('cc-mvd-2', 'camp-2', 'mvd');
      await guardar(zona('z-2', 'cc-mvd-2'));
      await guardar(zona('z-1', 'cc-mvd-1'));

      final zonas = await local.vivasDeCiudad('mvd');

      expect(
        [for (final z in zonas) (z.zona.id, z.campaniaId, z.ciudadId)],
        [('z-1', 'camp-1', 'mvd'), ('z-2', 'camp-2', 'mvd')],
      );
      expect(zonas.first.zona, zona('z-1', 'cc-mvd-1'));
    });

    test('deja afuera las zonas dadas de baja, las de una ciudad quitada de la campaña y las de '
        'otra ciudad', () async {
      await ciudadDeCampania('cc-viva', 'camp-1', 'mvd');
      await ciudadDeCampania('cc-quitada', 'camp-2', 'mvd', deBaja: true);
      await ciudadDeCampania('cc-otra', 'camp-1', 'canelones');
      await guardar(zona('z-viva', 'cc-viva'));
      await guardar(zona('z-baja', 'cc-viva', deBaja: true));
      await guardar(zona('z-quitada', 'cc-quitada'));
      await guardar(zona('z-otra', 'cc-otra'));

      final zonas = await local.vivasDeCiudad('mvd');

      expect([for (final z in zonas) z.zona.id], ['z-viva']);
    });

    test(
      'las tablas de catálogo aceptan las filas del delta y rechazan una forma fuera del CHECK',
      () async {
        await ciudadDeCampania('cc-1', 'camp-1', 'mvd');
        final vertice = ZonaVerticeModel(
          id: 'v-1',
          zonaId: 'z-1',
          orden: 1,
          lat: -34.9,
          lon: -56.1,
          calleA: 'Av. Italia',
          calleB: 'Bv. Artigas',
          auditoria: auditoria,
        );
        await db.into(db.zonaVertices).insert(vertice.aFila());
        final leido = await db.select(db.zonaVertices).getSingle();

        expect(ZonaVerticeModel.fromFila(leido), vertice);
        await expectLater(
          db
              .into(db.zonas)
              .insert(
                ZonaModel(
                  id: 'z-mala',
                  nombre: 'Radial sin radio',
                  campaniaCiudadId: 'cc-1',
                  tipoForma: 'RADIAL',
                  poligonoGeojson: const {'type': 'Polygon'},
                  auditoria: auditoria,
                ).aFila(),
              ),
          throwsA(anything),
        );
      },
    );
  });

  group('ZonaRepositoryImpl.vivasDeCiudad', () {
    test('devuelve cada zona con su geometría, lista para ubicar un punto', () async {
      await ciudadDeCampania('cc-1', 'camp-1', 'mvd');
      await guardar(zona('z-1', 'cc-1'));

      final r = await ZonaRepositoryImpl(local, logger: loggerMudo()).vivasDeCiudad('mvd');
      final zonas = r.getOrElse(() => throw StateError('era un Left'));

      expect(
        [for (final z in zonas) (z.zonaId, z.campaniaId, z.ciudadId)],
        [('z-1', 'camp-1', 'mvd')],
      );
      expect(zonas.single.geometria.cubre(const Coordenadas(lat: -34.9, lon: -56.15)), isTrue);
    });

    test('saltea la zona cuya forma no se puede leer y devuelve las demás', () async {
      await ciudadDeCampania('cc-1', 'camp-1', 'mvd');
      await guardar(
        zona(
          'z-rota',
          'cc-1',
          forma: const {
            'type': 'Point',
            'coordinates': [0, 0],
          },
        ),
      );
      await guardar(zona('z-sana', 'cc-1'));

      final r = await ZonaRepositoryImpl(local, logger: loggerMudo()).vivasDeCiudad('mvd');

      expect(r.getOrElse(() => throw StateError('era un Left')).map((z) => z.zonaId), ['z-sana']);
    });

    test('si la lectura falla, devuelve FailureInesperado', () async {
      final r = await ZonaRepositoryImpl(
        _LocalQueFalla(),
        logger: loggerMudo(),
      ).vivasDeCiudad('mvd');

      expect(r.swap().getOrElse(() => throw StateError('era un Right')), isA<FailureInesperado>());
    });
  });
}

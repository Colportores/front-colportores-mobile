// Migraciones de la DB local contra los esquemas congelados de `drift_schemas/` (convenciones §9).
//
// Lo genera `dart run drift_dev make-migrations` la primera vez y después se mantiene a mano; los
// `generated/schema_vN.dart` sí se regeneran con cada versión nueva. `SchemaVerifier` arma una DB
// con el esquema exacto de la versión N, corre `AppDatabase.migration` y compara el resultado con
// el esquema congelado de la versión destino: un paso `N → N+1` olvidado o que deja otra cosa
// rompe el test, y un `ALTER TABLE … ADD COLUMN` no da un falso fallo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'generated/schema.dart';
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;

class _SinSalida extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

AppDatabase _abrir(QueryExecutor e) => AppDatabase(e, logger: AppLogger(output: _SinSalida()));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verificador;

  setUpAll(() {
    verificador = SchemaVerifier(GeneratedHelper());
  });

  test('la última versión congelada es la de AppDatabase (falta correr make-migrations si no)', () {
    expect(GeneratedHelper.versions.last, AppDatabase.versionEsquema);
  });

  group('dado una DB en una versión anterior', () {
    const versiones = GeneratedHelper.versions;
    for (final (i, desde) in versiones.indexed) {
      for (final hasta in versiones.skip(i + 1)) {
        test('cuando migra de la $desde a la $hasta, queda igual al esquema congelado', () async {
          final esquema = await verificador.schemaAt(desde);
          final db = _abrir(esquema.newConnection());
          addTearDown(db.close);

          await verificador.migrateAndValidate(db, hasta);
        });
      }
    }
  });

  test('dado que la migración 2 → 3 falla en su último paso, no deja nada a medias y la próxima '
      'apertura migra bien conservando las jornadas', () async {
    // Un corte a mitad de camino (disco lleno, la app matada) sin transacción dejaba `ubicacion` y
    // su índice creados con `user_version = 2`: cada apertura siguiente fallaba en el mismo
    // `CREATE INDEX` y la DB quedaba inabrible. Se simula con un índice que ya ocupa el nombre del
    // último `CREATE INDEX` del paso.
    final esquema = await verificador.schemaAt(2);
    final crudo = esquema.rawDatabase
      ..execute(
        'INSERT INTO jornada (id, colportor_id, inicio, created_at, updated_at) '
        "VALUES ('jor-1', 'col-1', 1758700000000, 1758700000000, 1758700000000)",
      )
      ..execute('CREATE INDEX espacio_ubicacion_idx ON jornada (id)');

    final fallida = _abrir(esquema.newConnection());
    await expectLater(fallida.customSelect('SELECT 1').get(), throwsA(anything));
    await fallida.close().catchError((Object _) {});

    List<String> objetosNuevos() => [
      for (final fila in crudo.select(
        "SELECT name FROM sqlite_master WHERE name IN ('ubicacion', 'espacio', "
        "'ubicacion_ciudad_idx')",
      ))
        fila['name'] as String,
    ];
    expect(objetosNuevos(), isEmpty, reason: 'la transacción revirtió todo el paso');
    expect(crudo.userVersion, 2);
    expect(crudo.select('SELECT id FROM jornada').map((f) => f['id']), ['jor-1']);

    crudo.execute('DROP INDEX espacio_ubicacion_idx');
    final reintento = _abrir(esquema.newConnection());
    addTearDown(reintento.close);

    await verificador.migrateAndValidate(reintento, 3);
    expect(
      (await reintento.customSelect('SELECT id FROM jornada').get()).map((f) => f.data['id']),
      ['jor-1'],
    );
  });

  test(
    'dado jornadas guardadas en la versión 2, cuando migra a la 3, se conservan todas',
    () async {
      // Perder la información de un colportor cuesta mucho dinero (convenciones §9).
      const abierta = v2.JornadaData(
        id: 'jor-1',
        colportorId: 'col-1',
        inicio: 1758700000000,
        totalVisitas: 0,
        totalVentas: 0,
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        syncVersion: 0,
      );
      const cerrada = v2.JornadaData(
        id: 'jor-2',
        colportorId: 'col-1',
        inicio: 1758600000000,
        fin: 1758620000000,
        acompanianteId: 'col-2',
        tipoAcompaniamiento: 'CAPACITACION',
        totalVisitas: 12,
        totalVentas: 3,
        createdAt: 1758600000000,
        updatedAt: 1758620000000,
        createdBy: 'col-1',
        syncVersion: 4,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 2,
        newVersion: 3,
        createOld: v2.DatabaseAtV2.new,
        createNew: v3.DatabaseAtV3.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) => batch.insertAll(viejo.jornada, [abierta, cerrada]),
        validateItems: (nuevo) async {
          final filas = await (nuevo.select(
            nuevo.jornada,
          )..orderBy([(j) => OrderingTerm.asc(j.id)])).get();
          expect(filas.map((f) => f.toJson()).toList(), [abierta.toJson(), cerrada.toJson()]);
          expect(await nuevo.select(nuevo.ubicacion).get(), isEmpty);
          expect(await nuevo.select(nuevo.espacio).get(), isEmpty);
        },
      );
    },
  );

  test('dado jornadas, ubicaciones y espacios guardados en la versión 3, cuando migra a la 4, se '
      'conservan todos con los mismos datos', () async {
    const jornada = v3.JornadaData(
      id: 'jor-1',
      colportorId: 'col-1',
      inicio: 1758700000000,
      fin: 1758720000000,
      totalVisitas: 7,
      totalVentas: 2,
      createdAt: 1758700000000,
      updatedAt: 1758720000000,
      createdBy: 'col-1',
      syncVersion: 3,
    );
    const activa = v3.UbicacionData(
      id: 'ub-1',
      tipo: 'CASA',
      calle: 'Av. Ñandú',
      numero: '1234 bis',
      lat: -34.9,
      lon: -56.16,
      ciudadId: 'ciu-1',
      zonaId: 'zon-1',
      createdAt: 1758700000000,
      updatedAt: 1758710000000,
      createdBy: 'col-1',
      syncVersion: 5,
    );
    const deBaja = v3.UbicacionData(
      id: 'ub-2',
      tipo: 'EDIFICIO',
      lat: -34.91,
      lon: -56.17,
      ciudadId: 'ciu-1',
      createdAt: 1758600000000,
      updatedAt: 1758650000000,
      deletedAt: 1758650000000,
      syncVersion: 0,
    );
    const espacio = v3.EspacioData(
      id: 'esp-1',
      ubicacionId: 'ub-2',
      numeroDepto: '3B',
      piso: '3',
      descripcion: 'Fondo',
      createdAt: 1758600000000,
      updatedAt: 1758600000000,
      createdBy: 'col-1',
      syncVersion: 1,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 4,
      createOld: v3.DatabaseAtV3.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch
          ..insert(viejo.jornada, jornada)
          ..insertAll(viejo.ubicacion, [activa, deBaja])
          ..insert(viejo.espacio, espacio);
      },
      validateItems: (nuevo) async {
        final jornadas = await nuevo.select(nuevo.jornada).get();
        expect(jornadas.map((f) => f.toJson()).toList(), [jornada.toJson()]);
        final ubicaciones = await (nuevo.select(
          nuevo.ubicacion,
        )..orderBy([(u) => OrderingTerm.asc(u.id)])).get();
        expect(ubicaciones.map((f) => f.toJson()).toList(), [activa.toJson(), deBaja.toJson()]);
        final espacios = await nuevo.select(nuevo.espacio).get();
        expect(espacios.map((f) => f.toJson()).toList(), [espacio.toJson()]);
        expect(await nuevo.select(nuevo.ubicacionParDecidido).get(), isEmpty);
      },
    );
  });
}

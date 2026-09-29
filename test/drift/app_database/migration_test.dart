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
}

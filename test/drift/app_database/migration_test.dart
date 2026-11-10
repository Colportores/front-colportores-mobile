// Migraciones de la DB local contra los esquemas congelados de `drift_schemas/` (convenciones §9).
//
// Lo genera `dart run drift_dev make-migrations` la primera vez y después se mantiene a mano; los
// `generated/schema_vN.dart` sí se regeneran con cada versión nueva. `SchemaVerifier` arma una DB
// con el esquema exacto de la versión N, corre `AppDatabase.migration` y compara el resultado con
// el esquema congelado de la versión destino: un paso `N → N+1` olvidado o que deja otra cosa
// rompe el test, y un `ALTER TABLE … ADD COLUMN` no da un falso fallo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'generated/schema.dart';
import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v11.dart' as v11;
import 'generated/schema_v12.dart' as v12;
import 'generated/schema_v13.dart' as v13;
import 'generated/schema_v14.dart' as v14;
import 'generated/schema_v15.dart' as v15;
import 'generated/schema_v16.dart' as v16;
import 'generated/schema_v17.dart' as v17;
import 'generated/schema_v18.dart' as v18;
import 'generated/schema_v19.dart' as v19;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v20.dart' as v20;
import 'generated/schema_v21.dart' as v21;
import 'generated/schema_v22.dart' as v22;
import 'generated/schema_v23.dart' as v23;
import 'generated/schema_v24.dart' as v24;
import 'generated/schema_v25.dart' as v25;
import 'generated/schema_v26.dart' as v26;
import 'generated/schema_v27.dart' as v27;
import 'generated/schema_v28.dart' as v28;
import 'generated/schema_v29.dart' as v29;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v30.dart' as v30;
import 'generated/schema_v31.dart' as v31;
import 'generated/schema_v32.dart' as v32;
import 'generated/schema_v33.dart' as v33;
import 'generated/schema_v34.dart' as v34;
import 'generated/schema_v35.dart' as v35;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;
import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;

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

  test('dado jornadas, ubicaciones, espacios y pares decididos guardados en la versión 4, cuando '
      'migra a la 5, se conservan todos con los mismos datos y las zonas quedan vacías', () async {
    // #231: la zona de cada ubicación pasa a salir de su posición, pero la migración no la toca:
    // la de cada fila la sigue fijando el servidor, que gana.
    const jornada = v4.JornadaData(
      id: 'jor-1',
      colportorId: 'col-1',
      inicio: 1758700000000,
      fin: 1758720000000,
      acompanianteId: 'col-2',
      tipoAcompaniamiento: 'CAPACITACION',
      totalVisitas: 7,
      totalVentas: 2,
      createdAt: 1758700000000,
      updatedAt: 1758720000000,
      createdBy: 'col-1',
      syncVersion: 3,
    );
    const conZona = v4.UbicacionData(
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
    const sinZonaDeBaja = v4.UbicacionData(
      id: 'ub-2',
      tipo: 'EDIFICIO',
      lat: -34.9000001,
      lon: -56.1600001,
      ciudadId: 'ciu-1',
      createdAt: 1758600000000,
      updatedAt: 1758650000000,
      deletedAt: 1758650000000,
      syncVersion: 0,
    );
    const espacio = v4.EspacioData(
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
    const par = v4.UbicacionParDecididoData(
      ubicacionAId: 'ub-1',
      ubicacionBId: 'ub-2',
      decision: 'CONSERVAR_AMBOS',
      decididoEn: 1758660000000,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 4,
      newVersion: 5,
      createOld: v4.DatabaseAtV4.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch
          ..insert(viejo.jornada, jornada)
          ..insertAll(viejo.ubicacion, [conZona, sinZonaDeBaja])
          ..insert(viejo.espacio, espacio)
          ..insert(viejo.ubicacionParDecidido, par);
      },
      validateItems: (nuevo) async {
        final jornadas = await nuevo.select(nuevo.jornada).get();
        expect(jornadas.map((f) => f.toJson()).toList(), [jornada.toJson()]);
        final ubicaciones = await (nuevo.select(
          nuevo.ubicacion,
        )..orderBy([(u) => OrderingTerm.asc(u.id)])).get();
        expect(ubicaciones.map((f) => f.toJson()).toList(), [
          conZona.toJson(),
          sinZonaDeBaja.toJson(),
        ]);
        final espacios = await nuevo.select(nuevo.espacio).get();
        expect(espacios.map((f) => f.toJson()).toList(), [espacio.toJson()]);
        final pares = await nuevo.select(nuevo.ubicacionParDecidido).get();
        expect(pares.map((f) => f.toJson()).toList(), [par.toJson()]);
        expect(await nuevo.select(nuevo.campaniaCiudad).get(), isEmpty);
        expect(await nuevo.select(nuevo.zona).get(), isEmpty);
        expect(await nuevo.select(nuevo.zonaVertice).get(), isEmpty);
      },
    );
  });

  test('dado jornadas, ubicaciones, espacios y pares guardados en la versión 5, cuando migra a '
      'la 6, se conservan todos con los mismos datos y la copia del nombre queda vacía', () async {
    // #243: solo se suma `sesion_usuario`. Perder lo guardado de un colportor cuesta mucho dinero
    // (convenciones §9): nada de lo anterior puede moverse.
    const jornada = v5.JornadaData(
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
    const ubicacion = v5.UbicacionData(
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
    const espacio = v5.EspacioData(
      id: 'esp-1',
      ubicacionId: 'ub-1',
      numeroDepto: '3B',
      piso: '3',
      descripcion: 'Fondo',
      createdAt: 1758600000000,
      updatedAt: 1758600000000,
      createdBy: 'col-1',
      syncVersion: 1,
    );
    const par = v5.UbicacionParDecididoData(
      ubicacionAId: 'ub-1',
      ubicacionBId: 'ub-2',
      decision: 'CONSERVAR_AMBOS',
      decididoEn: 1758660000000,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 5,
      newVersion: 6,
      createOld: v5.DatabaseAtV5.new,
      createNew: v6.DatabaseAtV6.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch
          ..insert(viejo.jornada, jornada)
          ..insert(viejo.ubicacion, ubicacion)
          ..insert(viejo.espacio, espacio)
          ..insert(viejo.ubicacionParDecidido, par);
      },
      validateItems: (nuevo) async {
        final jornadas = await nuevo.select(nuevo.jornada).get();
        expect(jornadas.map((f) => f.toJson()).toList(), [jornada.toJson()]);
        final ubicaciones = await nuevo.select(nuevo.ubicacion).get();
        expect(ubicaciones.map((f) => f.toJson()).toList(), [ubicacion.toJson()]);
        final espacios = await nuevo.select(nuevo.espacio).get();
        expect(espacios.map((f) => f.toJson()).toList(), [espacio.toJson()]);
        final pares = await nuevo.select(nuevo.ubicacionParDecidido).get();
        expect(pares.map((f) => f.toJson()).toList(), [par.toJson()]);
        expect(await nuevo.select(nuevo.sesionUsuario).get(), isEmpty);
      },
    );
  });

  test(
    'dado jornadas, ubicaciones, espacios, pares y la copia del nombre guardados en la versión 6, '
    'cuando migra a la 7, se conservan todos con los mismos datos y la auditoría queda vacía',
    () async {
      // #205: solo se suma `audit_log`. Las bajas que ya había quedan sin motivo (la Lista no muestra
      // ninguno) y nada de lo guardado puede moverse (convenciones §9).
      const jornada = v6.JornadaData(
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
      const ubicacion = v6.UbicacionData(
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
      const deBaja = v6.UbicacionData(
        id: 'ub-2',
        tipo: 'NEGOCIO',
        lat: -34.91,
        lon: -56.17,
        ciudadId: 'ciu-1',
        createdAt: 1758700000000,
        updatedAt: 1758715000000,
        deletedAt: 1758715000000,
        createdBy: 'col-1',
        syncVersion: 2,
      );
      const espacio = v6.EspacioData(
        id: 'esp-1',
        ubicacionId: 'ub-1',
        numeroDepto: '3B',
        piso: '3',
        descripcion: 'Fondo',
        createdAt: 1758600000000,
        updatedAt: 1758600000000,
        createdBy: 'col-1',
        syncVersion: 1,
      );
      const par = v6.UbicacionParDecididoData(
        ubicacionAId: 'ub-1',
        ubicacionBId: 'ub-2',
        decision: 'CONSERVAR_AMBOS',
        decididoEn: 1758660000000,
      );
      const sesion = v6.SesionUsuarioData(usuarioId: 'col-1', nombre: 'Cristian');

      await verificador.testWithDataIntegrity(
        oldVersion: 6,
        newVersion: 7,
        createOld: v6.DatabaseAtV6.new,
        createNew: v7.DatabaseAtV7.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) {
          batch
            ..insert(viejo.jornada, jornada)
            ..insert(viejo.ubicacion, ubicacion)
            ..insert(viejo.ubicacion, deBaja)
            ..insert(viejo.espacio, espacio)
            ..insert(viejo.ubicacionParDecidido, par)
            ..insert(viejo.sesionUsuario, sesion);
        },
        validateItems: (nuevo) async {
          final jornadas = await nuevo.select(nuevo.jornada).get();
          expect(jornadas.map((f) => f.toJson()).toList(), [jornada.toJson()]);
          final ubicaciones = await (nuevo.select(
            nuevo.ubicacion,
          )..orderBy([(u) => OrderingTerm.asc(u.id)])).get();
          expect(ubicaciones.map((f) => f.toJson()).toList(), [
            ubicacion.toJson(),
            deBaja.toJson(),
          ]);
          final espacios = await nuevo.select(nuevo.espacio).get();
          expect(espacios.map((f) => f.toJson()).toList(), [espacio.toJson()]);
          final pares = await nuevo.select(nuevo.ubicacionParDecidido).get();
          expect(pares.map((f) => f.toJson()).toList(), [par.toJson()]);
          final sesiones = await nuevo.select(nuevo.sesionUsuario).get();
          expect(sesiones.map((f) => f.toJson()).toList(), [sesion.toJson()]);
          expect(await nuevo.select(nuevo.auditLog).get(), isEmpty);
        },
      );
    },
  );

  test(
    'dado lo guardado en la versión 7, cuando migra a la 8, se conserva todo y la cola del motor '
    'queda vacía',
    () async {
      // #178: solo se suman `sync_queue` y `sync_watermark`. Nada de lo guardado se encola al
      // migrar: antes de la 8 no había motor y encolar fallaba, así que no hay un alta guardada
      // sin su job (convenciones §9).
      const jornada = v7.JornadaData(
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
      const ubicacion = v7.UbicacionData(
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
      const auditoria = v7.AuditLogData(
        id: 1,
        evento: 'ubicacion_baja',
        uuid: 'ub-1',
        motivo: 'Se mudaron',
        creadoEn: 1758715000000,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 7,
        newVersion: 8,
        createOld: v7.DatabaseAtV7.new,
        createNew: v8.DatabaseAtV8.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) {
          batch
            ..insert(viejo.jornada, jornada)
            ..insert(viejo.ubicacion, ubicacion)
            ..insert(viejo.auditLog, auditoria);
        },
        validateItems: (nuevo) async {
          final jornadas = await nuevo.select(nuevo.jornada).get();
          expect(jornadas.map((f) => f.toJson()).toList(), [jornada.toJson()]);
          final ubicaciones = await nuevo.select(nuevo.ubicacion).get();
          expect(ubicaciones.map((f) => f.toJson()).toList(), [ubicacion.toJson()]);
          final auditorias = await nuevo.select(nuevo.auditLog).get();
          expect(auditorias.map((f) => f.toJson()).toList(), [auditoria.toJson()]);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);
          expect(await nuevo.select(nuevo.syncWatermark).get(), isEmpty);
        },
      );
    },
  );

  test(
    'dado lo guardado en la versión 8, cuando migra a la 9, se conserva todo y las tablas de las '
    'personas quedan vacías',
    () async {
      // HU-UBI-008 (#140): solo se suman `persona`, `espacio_persona` y `nota`. Nada de lo guardado
      // cambia ni se encola al migrar (convenciones §9).
      const ubicacion = v8.UbicacionData(
        id: 'ub-1',
        tipo: 'EDIFICIO',
        calle: 'Mataojo',
        numero: '2044',
        lat: -34.9,
        lon: -56.16,
        ciudadId: 'ciu-1',
        zonaId: 'zon-1',
        createdAt: 1758700000000,
        updatedAt: 1758710000000,
        createdBy: 'col-1',
        syncVersion: 5,
      );
      const espacio = v8.EspacioData(
        id: 'esp-1',
        ubicacionId: 'ub-1',
        numeroDepto: '3B',
        createdAt: 1758700000000,
        updatedAt: 1758710000000,
        createdBy: 'col-1',
        syncVersion: 2,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 8,
        newVersion: 9,
        createOld: v8.DatabaseAtV8.new,
        createNew: v9.DatabaseAtV9.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) {
          batch
            ..insert(viejo.ubicacion, ubicacion)
            ..insert(viejo.espacio, espacio);
        },
        validateItems: (nuevo) async {
          final ubicaciones = await nuevo.select(nuevo.ubicacion).get();
          expect(ubicaciones.map((f) => f.toJson()).toList(), [ubicacion.toJson()]);
          final espacios = await nuevo.select(nuevo.espacio).get();
          expect(espacios.map((f) => f.toJson()).toList(), [espacio.toJson()]);
          expect(await nuevo.select(nuevo.persona).get(), isEmpty);
          expect(await nuevo.select(nuevo.espacioPersona).get(), isEmpty);
          expect(await nuevo.select(nuevo.nota).get(), isEmpty);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);
        },
      );
    },
  );

  test('dado lo guardado en la versión 9, cuando migra a la 10, se conserva todo y la agenda, las '
      'visitas y la cache del color quedan vacías', () async {
    // BACK-HU-VIS-001 (#404): solo se suman `agenda`, `visita` y `house_status`. Nada de lo
    // guardado cambia ni se encola al migrar (convenciones §9, y nunca se pierde una persona).
    const ubicacion = v9.UbicacionData(
      id: 'ub-1',
      tipo: 'CASA',
      calle: 'Mataojo',
      numero: '2044',
      lat: -34.9,
      lon: -56.16,
      ciudadId: 'ciu-1',
      zonaId: 'zon-1',
      createdAt: 1758700000000,
      updatedAt: 1758710000000,
      createdBy: 'col-1',
      syncVersion: 5,
    );
    const persona = v9.PersonaData(
      id: 'per-1',
      nombre: 'Ana',
      apellido: 'Martínez',
      telefono: '099123456',
      notasGlobales: 'prefiere de tarde',
      createdAt: 1758700000000,
      updatedAt: 1758710000000,
      createdBy: 'col-1',
      syncVersion: 0,
    );
    const vinculo = v9.EspacioPersonaData(
      id: 'ep-1',
      espacioId: 'esp-1',
      personaId: 'per-1',
      createdAt: 1758700000000,
      updatedAt: 1758710000000,
      createdBy: 'col-1',
      syncVersion: 2,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 9,
      newVersion: 10,
      createOld: v9.DatabaseAtV9.new,
      createNew: v10.DatabaseAtV10.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch
          ..insert(viejo.ubicacion, ubicacion)
          ..insert(viejo.persona, persona)
          ..insert(viejo.espacioPersona, vinculo);
      },
      validateItems: (nuevo) async {
        final ubicaciones = await nuevo.select(nuevo.ubicacion).get();
        expect(ubicaciones.map((f) => f.toJson()).toList(), [ubicacion.toJson()]);
        final personas = await nuevo.select(nuevo.persona).get();
        expect(personas.map((f) => f.toJson()).toList(), [persona.toJson()]);
        final vinculos = await nuevo.select(nuevo.espacioPersona).get();
        expect(vinculos.map((f) => f.toJson()).toList(), [vinculo.toJson()]);
        expect(await nuevo.select(nuevo.agenda).get(), isEmpty);
        expect(await nuevo.select(nuevo.visita).get(), isEmpty);
        expect(await nuevo.select(nuevo.houseStatus).get(), isEmpty);
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);
      },
    );
  });

  test('dado lo guardado en la versión 10, cuando migra a la 11, las visitas y las agendas conservan '
      'todo, toman el espacio de su vínculo y la agenda pasa a los estados de la HU', () async {
    // #411: `visita` y `agenda` cuelgan del espacio y la persona es opcional. Nada se pierde ni se
    // encola al migrar (convenciones §9; nunca se pierde una venta ni una persona).
    const vinculo = v10.EspacioPersonaData(
      id: 'ep-1',
      espacioId: 'esp-1',
      personaId: 'per-1',
      createdAt: 1758700000000,
      updatedAt: 1758710000000,
      createdBy: 'col-1',
      syncVersion: 2,
    );
    const visita = v10.VisitaData(
      id: 'vis-1',
      espacioPersonaId: 'ep-1',
      fecha: 1758720000000,
      tipoResultado: 'ENTREVISTA',
      colportorId: 'col-1',
      createdAt: 1758720000000,
      updatedAt: 1758720000000,
      createdBy: 'col-1',
      syncVersion: 3,
    );
    const visitaSinVinculo = v10.VisitaData(
      id: 'vis-2',
      espacioPersonaId: 'ep-que-no-llego',
      fecha: 1758730000000,
      tipoResultado: 'NO_CONTESTO',
      colportorId: 'col-1',
      createdAt: 1758730000000,
      updatedAt: 1758730000000,
      syncVersion: 0,
    );
    v10.AgendaData agenda(String id, String estado, {String? visitaId}) => v10.AgendaData(
      id: id,
      espacioPersonaId: 'ep-1',
      tipo: 'ENTREVISTA',
      fechaProgramada: 1758800000000,
      esEstricta: 0,
      estado: estado,
      colportorId: 'col-1',
      visitaId: visitaId,
      createdAt: 1758700000000,
      updatedAt: 1758710000000,
      createdBy: 'col-1',
      syncVersion: 1,
    );
    final agendas = [
      agenda('ag-1', 'PENDIENTE'),
      agenda('ag-2', 'COMPLETADA', visitaId: 'vis-1'),
      agenda('ag-3', 'CANCELADA'),
    ];

    await verificador.testWithDataIntegrity(
      oldVersion: 10,
      newVersion: 11,
      createOld: v10.DatabaseAtV10.new,
      createNew: v11.DatabaseAtV11.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch
          ..insert(viejo.espacioPersona, vinculo)
          ..insert(viejo.visita, visita)
          ..insert(viejo.visita, visitaSinVinculo);
        for (final a in agendas) {
          batch.insert(viejo.agenda, a);
        }
      },
      validateItems: (nuevo) async {
        final visitas = {for (final v in await nuevo.select(nuevo.visita).get()) v.id: v};
        expect(visitas.keys, unorderedEquals(['vis-1', 'vis-2']));
        expect(visitas['vis-1']!.espacioId, 'esp-1');
        expect(visitas['vis-1']!.espacioPersonaId, 'ep-1');
        expect(visitas['vis-1']!.tipoResultado, 'ENTREVISTA');
        expect(visitas['vis-1']!.fecha, visita.fecha);
        expect(visitas['vis-1']!.syncVersion, 3);
        // Un vínculo que todavía no llegó: no se inventa un espacio, y la visita no se pierde.
        expect(visitas['vis-2']!.espacioId, '');
        expect(visitas['vis-2']!.espacioPersonaId, 'ep-que-no-llego');

        final filas = {for (final a in await nuevo.select(nuevo.agenda).get()) a.id: a};
        expect(filas.keys, unorderedEquals(['ag-1', 'ag-2', 'ag-3']));
        expect(filas['ag-1']!.estado, 'PROGRAMADA');
        expect(filas['ag-2']!.estado, 'CUMPLIDA');
        expect(filas['ag-2']!.visitaId, 'vis-1');
        expect(filas['ag-3']!.estado, 'CANCELADA');
        for (final a in filas.values) {
          expect(a.espacioId, 'esp-1');
          expect(a.espacioPersonaId, 'ep-1');
          expect(a.fechaProgramada, 1758800000000);
        }
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

        // El esquema nuevo admite lo que el viejo no: visita sin persona, `COBRANZA` y `NO_CUMPLIDA`.
        await nuevo.customStatement(
          'INSERT INTO visita (id, espacio_id, fecha, tipo_resultado, colportor_id, created_at, '
          "updated_at, sync_version) VALUES ('vis-3', 'esp-1', 1, 'COBRANZA', 'col-1', 1, 1, 0)",
        );
        await nuevo.customStatement("UPDATE agenda SET estado = 'NO_CUMPLIDA' WHERE id = 'ag-1'");
      },
    );
  });

  test('dado lo guardado en la versión 11, cuando migra a la 12, no se pierde nada y aparece el '
      'historial de avisos vacío y sin encolar nada', () async {
    // #156: `notificacion_historial` es local-only (no se sincroniza): al migrar solo se crea.
    const jornada = v11.JornadaData(
      id: 'jor-1',
      colportorId: 'col-1',
      inicio: 1758700000000,
      totalVisitas: 0,
      totalVentas: 0,
      createdAt: 1758700000000,
      updatedAt: 1758700000000,
      createdBy: 'col-1',
      syncVersion: 1,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 11,
      newVersion: 12,
      createOld: v11.DatabaseAtV11.new,
      createNew: v12.DatabaseAtV12.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) => batch.insert(viejo.jornada, jornada),
      validateItems: (nuevo) async {
        final jornadas = await nuevo.select(nuevo.jornada).get();
        expect(jornadas.map((j) => j.id), ['jor-1']);
        expect(jornadas.single.syncVersion, 1);
        expect(await nuevo.select(nuevo.notificacionHistorial).get(), isEmpty);
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

        // La tabla nueva guarda un aviso y rechaza repetir el id.
        await nuevo.customStatement(
          'INSERT INTO notificacion_historial (id, tipo, titulo, recibida_en) '
          "VALUES ('n-1', 'RECORDATORIO_VISITA', 'Cobranza a las 16:00', 1)",
        );
        await expectLater(
          nuevo.customStatement(
            'INSERT INTO notificacion_historial (id, tipo, titulo, recibida_en) '
            "VALUES ('n-1', 'RECORDATORIO_VISITA', 'otro', 2)",
          ),
          throwsA(anything),
        );
      },
    );
  });

  test('dado lo guardado en la versión 12, cuando migra a la 13, no se pierde nada y aparece la '
      'tabla de metadatos del motor vacía y sin encolar nada', () async {
    // #486: `sync_meta` es solo local (infraestructura del motor): al migrar solo se crea. La vista
    // de estado de sync dice «Todavía no hubo» hasta que el motor anote algo.
    const jornada = v12.JornadaData(
      id: 'jor-1',
      colportorId: 'col-1',
      inicio: 1758700000000,
      totalVisitas: 0,
      totalVentas: 0,
      createdAt: 1758700000000,
      updatedAt: 1758700000000,
      createdBy: 'col-1',
      syncVersion: 1,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 12,
      newVersion: 13,
      createOld: v12.DatabaseAtV12.new,
      createNew: v13.DatabaseAtV13.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) => batch.insert(viejo.jornada, jornada),
      validateItems: (nuevo) async {
        final jornadas = await nuevo.select(nuevo.jornada).get();
        expect(jornadas.map((j) => j.id), ['jor-1']);
        expect(jornadas.single.syncVersion, 1);
        expect(await nuevo.select(nuevo.syncMeta).get(), isEmpty);
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

        // La tabla nueva guarda un dato y rechaza repetir la clave.
        await nuevo.customStatement(
          "INSERT INTO sync_meta (clave, valor) VALUES ('last_pull_at', '2026-10-27T08:00:00.000Z')",
        );
        await expectLater(
          nuevo.customStatement(
            "INSERT INTO sync_meta (clave, valor) VALUES ('last_pull_at', 'otro')",
          ),
          throwsA(anything),
        );
      },
    );
  });

  test('dado la versión 13, cuando migra a la 14, crea las réplicas del catálogo vacías y no toca '
      'lo guardado', () async {
    const jornada = v13.JornadaData(
      id: 'jor-1',
      colportorId: 'col-1',
      inicio: 1758700000000,
      totalVisitas: 0,
      totalVentas: 0,
      createdAt: 1758700000000,
      updatedAt: 1758700000000,
      createdBy: 'col-1',
      syncVersion: 1,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 13,
      newVersion: 14,
      createOld: v13.DatabaseAtV13.new,
      createNew: v14.DatabaseAtV14.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) => batch.insert(viejo.jornada, jornada),
      validateItems: (nuevo) async {
        final jornadas = await nuevo.select(nuevo.jornada).get();
        expect(jornadas.map((j) => j.id), ['jor-1']);
        expect(await nuevo.select(nuevo.producto).get(), isEmpty);
        expect(await nuevo.select(nuevo.coleccion).get(), isEmpty);
        expect(await nuevo.select(nuevo.productoColeccion).get(), isEmpty);
        expect(await nuevo.select(nuevo.precioPorCiudad).get(), isEmpty);
        expect(await nuevo.select(nuevo.precioGeneral).get(), isEmpty);
      },
    );
  });

  test('dado la versión 14, cuando migra a la 15, crea la réplica del stock vacía y no toca '
      'lo guardado', () async {
    const jornada = v14.JornadaData(
      id: 'jor-1',
      colportorId: 'col-1',
      inicio: 1758700000000,
      totalVisitas: 0,
      totalVentas: 0,
      createdAt: 1758700000000,
      updatedAt: 1758700000000,
      createdBy: 'col-1',
      syncVersion: 1,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 14,
      newVersion: 15,
      createOld: v14.DatabaseAtV14.new,
      createNew: v15.DatabaseAtV15.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) => batch.insert(viejo.jornada, jornada),
      validateItems: (nuevo) async {
        final jornadas = await nuevo.select(nuevo.jornada).get();
        expect(jornadas.map((j) => j.id), ['jor-1']);
        expect(await nuevo.select(nuevo.stock).get(), isEmpty);
        // Nada se encola al migrar: el stock es una réplica de solo lectura.
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);
      },
    );
  });

  test(
    'dado la versión 15 con una bajada anotada, cuando migra a la 16, crea las réplicas de ciudad y '
    'de las campañas del colportor vacías, no toca lo guardado y olvida la última bajada',
    () async {
      const jornada = v15.JornadaData(
        id: 'jor-1',
        colportorId: 'col-1',
        inicio: 1758700000000,
        totalVisitas: 0,
        totalVentas: 0,
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        createdBy: 'col-1',
        syncVersion: 1,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 15,
        newVersion: 16,
        createOld: v15.DatabaseAtV15.new,
        createNew: v16.DatabaseAtV16.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) {
          batch.insert(viejo.jornada, jornada);
          batch.insertAll(viejo.syncMeta, [
            const v15.SyncMetaData(clave: 'last_pull_at', valor: '2026-10-20T12:00:00.000Z'),
            const v15.SyncMetaData(clave: 'last_backup_at', valor: '2026-10-19T12:00:00.000Z'),
          ]);
        },
        validateItems: (nuevo) async {
          final jornadas = await nuevo.select(nuevo.jornada).get();
          expect(jornadas.map((j) => j.id), ['jor-1']);
          expect(await nuevo.select(nuevo.ciudad).get(), isEmpty);
          expect(await nuevo.select(nuevo.campania).get(), isEmpty);
          expect(await nuevo.select(nuevo.campaniaColportor).get(), isEmpty);
          // Las réplicas nuevas todavía no bajaron: «hubo una bajada» ya no se puede afirmar, y lo
          // demás que el motor anotó se queda.
          final meta = {for (final f in await nuevo.select(nuevo.syncMeta).get()) f.clave: f.valor};
          expect(meta, {'last_backup_at': '2026-10-19T12:00:00.000Z'});
          // Nada se encola al migrar: son réplicas de solo lectura.
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);
        },
      );
    },
  );

  test('dado la versión 14 con jornadas guardadas, cuando migra de una vez a la 16 (stock y las '
      'réplicas de campañas), se conservan y las dos réplicas nacen vacías', () async {
    const jornada = v14.JornadaData(
      id: 'jor-1',
      colportorId: 'col-1',
      inicio: 1758700000000,
      totalVisitas: 0,
      totalVentas: 0,
      createdAt: 1758700000000,
      updatedAt: 1758700000000,
      createdBy: 'col-1',
      syncVersion: 1,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 14,
      newVersion: 16,
      createOld: v14.DatabaseAtV14.new,
      createNew: v16.DatabaseAtV16.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) => batch.insert(viejo.jornada, jornada),
      validateItems: (nuevo) async {
        final jornadas = await nuevo.select(nuevo.jornada).get();
        expect(jornadas.map((j) => j.id), ['jor-1']);
        expect(await nuevo.select(nuevo.stock).get(), isEmpty);
        expect(await nuevo.select(nuevo.ciudad).get(), isEmpty);
        expect(await nuevo.select(nuevo.campania).get(), isEmpty);
        expect(await nuevo.select(nuevo.campaniaColportor).get(), isEmpty);
      },
    );
  });

  test('dado lo guardado en la versión 16, cuando migra a la 17, no se pierde nada y aparecen la venta '
      'y sus ítems vacíos, con los CHECK del servidor y sin encolar nada', () async {
    // HU-VEN-001 (#423): `venta` y `venta_item` suben por el motor; al migrar solo se crean.
    const jornada = v16.JornadaData(
      id: 'jor-1',
      colportorId: 'col-1',
      inicio: 1758700000000,
      totalVisitas: 0,
      totalVentas: 0,
      createdAt: 1758700000000,
      updatedAt: 1758700000000,
      createdBy: 'col-1',
      syncVersion: 1,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 16,
      newVersion: 17,
      createOld: v16.DatabaseAtV16.new,
      createNew: v17.DatabaseAtV17.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) => batch.insert(viejo.jornada, jornada),
      validateItems: (nuevo) async {
        final jornadas = await nuevo.select(nuevo.jornada).get();
        expect(jornadas.map((j) => j.id), ['jor-1']);
        expect(await nuevo.select(nuevo.venta).get(), isEmpty);
        expect(await nuevo.select(nuevo.ventaItem).get(), isEmpty);
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

        const venta =
            'INSERT INTO venta (id, espacio_persona_id, numero_talonario, monto_total, fecha, '
            "colportor_id, created_at, updated_at) VALUES ('v-1', 'ep-1', '0042', 1200, 1, 'col-1', 1, 1)";
        await nuevo.customStatement(venta);
        // Un producto suelto: bien. Un combo sin `componentes`, o un ítem con producto y combo, no.
        const columnas =
            'INSERT INTO venta_item (id, venta_id, producto_id, coleccion_id, cantidad, '
            'precio_unitario, subtotal, componentes, created_at, updated_at) VALUES ';
        await nuevo.customStatement(
          "$columnas('i-1', 'v-1', 'p-1', NULL, 2, 600, 1200, NULL, 1, 1)",
        );
        for (final malo in [
          "('i-2', 'v-1', NULL, 'c-1', 1, 600, 600, NULL, 1, 1)",
          "('i-3', 'v-1', 'p-1', 'c-1', 1, 600, 600, '[]', 1, 1)",
          "('i-4', 'v-1', 'p-1', NULL, 2, 600, 999, NULL, 1, 1)",
          "('i-5', 'v-1', 'p-1', NULL, 0, 600, 0, NULL, 1, 1)",
        ]) {
          await expectLater(nuevo.customStatement('$columnas$malo'), throwsA(anything));
        }
        await expectLater(
          nuevo.customStatement(venta.replaceFirst("'v-1'", "'v-2'").replaceFirst('1200', '-1')),
          throwsA(anything),
        );
      },
    );
  });

  test(
    'dado lo guardado en la versión 17, cuando migra a la 18, el producto conserva todo, queda sin '
    'código del editor, aparece parametro_global vacío y no se encola nada',
    () async {
      // HU-CAT-006 (#419): `producto.codigo_editor` es una columna nueva y opcional, y `parametro_global`
      // una réplica de solo lectura que llena el pull. Al migrar no se toca nada de lo guardado.
      const producto = v17.ProductoData(
        id: 'pro-1',
        nombre: 'El Conflicto de los Siglos',
        tipo: 'LIBRO',
        esBonificable: 1,
        esMisionero: 0,
        precioBaseCompra: 18000,
        casaEditora: 'ACES',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        syncVersion: 3,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 17,
        newVersion: 18,
        createOld: v17.DatabaseAtV17.new,
        createNew: v18.DatabaseAtV18.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) => batch.insert(viejo.producto, producto),
        validateItems: (nuevo) async {
          final productos = await nuevo.select(nuevo.producto).get();
          expect(productos.map((p) => p.id), ['pro-1']);
          expect(productos.single.nombre, 'El Conflicto de los Siglos');
          expect(productos.single.precioBaseCompra, 18000);
          expect(productos.single.syncVersion, 3);
          expect(productos.single.codigoEditor, isNull);
          expect(await nuevo.select(nuevo.parametroGlobal).get(), isEmpty);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          // La columna acepta un código; la tabla nueva, una fila como la del servidor.
          await nuevo.customStatement(
            "UPDATE producto SET codigo_editor = 'CS-01' WHERE id = 'pro-1'",
          );
          await nuevo.customStatement(
            'INSERT INTO parametro_global (id, clave, valor, created_at, updated_at) '
            "VALUES ('pg-1', 'dias_antiguedad_precios', 15, 1, 1)",
          );
          expect((await nuevo.select(nuevo.producto).getSingle()).codigoEditor, 'CS-01');
          expect((await nuevo.select(nuevo.parametroGlobal).getSingle()).valor, 15);
        },
      );
    },
  );

  test(
    'dado lo guardado en la versión 18, cuando migra a la 19, no se pierde nada y aparece el cobro '
    'vacío, con los CHECK del servidor y sin encolar nada',
    () async {
      // HU-COB-001 (#436): `cobranza` sube por el motor; al migrar solo se crea.
      const venta = v18.VentaData(
        id: 'v-1',
        espacioPersonaId: 'ep-1',
        numeroTalonario: '0042',
        montoTotal: 1200,
        fecha: 1,
        colportorId: 'col-1',
        createdAt: 1,
        updatedAt: 1,
        syncVersion: 0,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 18,
        newVersion: 19,
        createOld: v18.DatabaseAtV18.new,
        createNew: v19.DatabaseAtV19.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) => batch.insert(viejo.venta, venta),
        validateItems: (nuevo) async {
          final ventas = await nuevo.select(nuevo.venta).get();
          expect(ventas.map((v) => v.id), ['v-1']);
          expect(await nuevo.select(nuevo.cobranza).get(), isEmpty);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          const columnas =
              'INSERT INTO cobranza (id, venta_id, monto, medio, fecha, created_at, updated_at) '
              'VALUES ';
          await nuevo.customStatement("$columnas('c-1', 'v-1', 500, 'EFECTIVO', 1, 1, 1)");
          for (final malo in [
            "('c-2', 'v-1', 0, 'EFECTIVO', 1, 1, 1)",
            "('c-3', 'v-1', -5, 'EFECTIVO', 1, 1, 1)",
            "('c-4', 'v-1', 500, 'CHEQUE', 1, 1, 1)",
          ]) {
            await expectLater(nuevo.customStatement('$columnas$malo'), throwsA(anything));
          }
        },
      );
    },
  );

  test('dado un cobro en efectivo guardado en la versión 19, cuando migra a la 20, no se pierde nada, '
      'los datos de la tarjeta y de la transferencia quedan vacíos y no se encola nada', () async {
    // HU-COB-002 y HU-COB-003 (#396): cinco columnas opcionales nuevas en `cobranza`.
    const venta = v19.VentaData(
      id: 'v-1',
      espacioPersonaId: 'ep-1',
      numeroTalonario: '0042',
      montoTotal: 4500,
      fecha: 1,
      colportorId: 'col-1',
      createdAt: 1,
      updatedAt: 1,
      syncVersion: 0,
    );
    const cobro = v19.CobranzaData(
      id: 'c-1',
      ventaId: 'v-1',
      monto: 500,
      medio: 'EFECTIVO',
      fecha: 1,
      createdAt: 1,
      updatedAt: 1,
      syncVersion: 2,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 19,
      newVersion: 20,
      createOld: v19.DatabaseAtV19.new,
      createNew: v20.DatabaseAtV20.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch.insert(viejo.venta, venta);
        batch.insert(viejo.cobranza, cobro);
      },
      validateItems: (nuevo) async {
        final cobros = await nuevo.select(nuevo.cobranza).get();
        expect(cobros.map((c) => c.id), ['c-1']);
        expect(cobros.single.monto, 500);
        expect(cobros.single.medio, 'EFECTIVO');
        expect(cobros.single.syncVersion, 2);
        expect(cobros.single.tarjetaTipo, isNull);
        expect(cobros.single.tarjetaMarca, isNull);
        expect(cobros.single.numeroAprobacion, isNull);
        expect(cobros.single.referenciaTransferencia, isNull);
        expect(cobros.single.bancoOrigen, isNull);
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

        // Las columnas aceptan lo que llevan el cobro con tarjeta y el de transferencia.
        await nuevo.customStatement(
          "UPDATE cobranza SET medio = 'TARJETA', tarjeta_tipo = 'DEBITO', tarjeta_marca = 'Visa', "
          "numero_aprobacion = '884213' WHERE id = 'c-1'",
        );
        final tarjeta = await nuevo.select(nuevo.cobranza).getSingle();
        expect(tarjeta.tarjetaTipo, 'DEBITO');
        expect(tarjeta.tarjetaMarca, 'Visa');
        expect(tarjeta.numeroAprobacion, '884213');
        await nuevo.customStatement(
          "UPDATE cobranza SET medio = 'TRANSFERENCIA', tarjeta_tipo = NULL, tarjeta_marca = NULL, "
          "numero_aprobacion = NULL, referencia_transferencia = 'TX-12345', banco_origen = 'BROU' "
          "WHERE id = 'c-1'",
        );
        final transferencia = await nuevo.select(nuevo.cobranza).getSingle();
        expect(transferencia.referenciaTransferencia, 'TX-12345');
        expect(transferencia.bancoOrigen, 'BROU');
      },
    );
  });

  test(
    'dado lo guardado en la versión 20, cuando migra a la 21, no se pierde nada y aparece la entrega '
    'vacía, con su CHECK y sin encolar nada',
    () async {
      // HU-VEN-002 (#430): `entrega` sube por el motor; al migrar solo se crea.
      const venta = v20.VentaData(
        id: 'v-1',
        espacioPersonaId: 'ep-1',
        numeroTalonario: '0042',
        montoTotal: 1200,
        fecha: 1,
        colportorId: 'col-1',
        createdAt: 1,
        updatedAt: 1,
        syncVersion: 0,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 20,
        newVersion: 21,
        createOld: v20.DatabaseAtV20.new,
        createNew: v21.DatabaseAtV21.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) => batch.insert(viejo.venta, venta),
        validateItems: (nuevo) async {
          final ventas = await nuevo.select(nuevo.venta).get();
          expect(ventas.map((v) => v.id), ['v-1']);
          expect(await nuevo.select(nuevo.entrega).get(), isEmpty);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          const columnas =
              'INSERT INTO entrega (id, venta_id, producto_id, cantidad, created_at, updated_at) '
              'VALUES ';
          await nuevo.customStatement("$columnas('e-1', 'v-1', 'p-1', 3, 1, 1)");
          final entrega = await nuevo.select(nuevo.entrega).getSingle();
          // Sin decir nada, la fila queda pendiente (el valor por defecto del servidor).
          expect(entrega.pendiente, 1);
          expect(entrega.fechaEntrega, isNull);
          for (final malo in [
            "('e-2', 'v-1', 'p-1', 0, 1, 1)",
            "('e-3', 'v-1', 'p-1', -2, 1, 1)",
          ]) {
            await expectLater(nuevo.customStatement('$columnas$malo'), throwsA(anything));
          }
        },
      );
    },
  );

  test(
    'dado lo guardado en la versión 21, cuando migra a la 22, no se pierde nada y aparece la devolución '
    'vacía, con sus CHECK y sin encolar nada',
    () async {
      // HU-VEN-004 (#161): `devolucion` sube por el motor; al migrar solo se crea.
      const venta = v21.VentaData(
        id: 'v-1',
        espacioPersonaId: 'ep-1',
        numeroTalonario: '0042',
        montoTotal: 1200,
        fecha: 1,
        colportorId: 'col-1',
        createdAt: 1,
        updatedAt: 1,
        syncVersion: 0,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 21,
        newVersion: 22,
        createOld: v21.DatabaseAtV21.new,
        createNew: v22.DatabaseAtV22.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) => batch.insert(viejo.venta, venta),
        validateItems: (nuevo) async {
          final ventas = await nuevo.select(nuevo.venta).get();
          expect(ventas.map((v) => v.id), ['v-1']);
          expect(await nuevo.select(nuevo.devolucion).get(), isEmpty);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          const columnas =
              'INSERT INTO devolucion (id, venta_id, productos_devueltos, dinero_retenido, '
              'monto_reembolsado, motivo, fecha_devolucion, created_at, updated_at) VALUES ';
          const libros = "'[{\"producto_id\":\"p-1\",\"cantidad\":1,\"venta_item_id\":\"i-1\"}]'";
          await nuevo.customStatement("$columnas('d-1', 'v-1', $libros, 0, NULL, NULL, 1, 1, 1)");
          await nuevo.customStatement("$columnas('d-2', 'v-1', $libros, 100, 50, 'x', 1, 1, 1)");
          expect(await nuevo.select(nuevo.devolucion).get(), hasLength(2));
          for (final malo in [
            "('d-3', 'v-1', $libros, -1, NULL, NULL, 1, 1, 1)",
            "('d-4', 'v-1', $libros, 0, -5, NULL, 1, 1, 1)",
            "('d-5', 'v-1', $libros, 0, NULL, '', 1, 1, 1)",
            "('d-6', 'v-1', $libros, 0, NULL, '${'a' * 501}', 1, 1, 1)",
          ]) {
            await expectLater(nuevo.customStatement('$columnas$malo'), throwsA(anything));
          }
        },
      );
    },
  );

  test(
    'dado lo guardado en la versión 22, cuando migra a la 23, no se pierde nada y aparece el depósito '
    'vacío, con sus CHECK y sin encolar nada',
    () async {
      // HU-CTA-004 (#442): `deposito` sube por el motor; al migrar solo se crea.
      const entrega = v22.EntregaData(
        id: 'e-1',
        ventaId: 'v-1',
        productoId: 'p-1',
        cantidad: 3,
        pendiente: 0,
        createdAt: 1,
        updatedAt: 1,
        syncVersion: 0,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 22,
        newVersion: 23,
        createOld: v22.DatabaseAtV22.new,
        createNew: v23.DatabaseAtV23.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) => batch.insert(viejo.entrega, entrega),
        validateItems: (nuevo) async {
          expect((await nuevo.select(nuevo.entrega).get()).map((e) => e.id), ['e-1']);
          expect(await nuevo.select(nuevo.deposito).get(), isEmpty);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          const columnas =
              'INSERT INTO deposito (id, monto, fecha, destino, concepto, campania_id, ticket_id, '
              'created_at, updated_at) VALUES ';
          await nuevo.customStatement(
            "$columnas('d-1', 180000, 1, 'BANCO', 'CASA_EDITORA', NULL, 't-1', 1, 1)",
          );
          final deposito = await nuevo.select(nuevo.deposito).getSingle();
          expect(deposito.monto, 180000);
          expect(deposito.destino, 'BANCO');
          expect(deposito.ticketId, 't-1');
          expect(deposito.syncVersion, 0);
          for (final malo in [
            "('d-2', 0, 1, 'BANCO', 'CASA_EDITORA', NULL, 't-2', 1, 1)",
            "('d-3', 100, 1, 'CAJERO', 'CASA_EDITORA', NULL, 't-3', 1, 1)",
            "('d-4', 100, 1, 'BANCO', 'OTRO', NULL, 't-4', 1, 1)",
            "('d-5', 100, 1, 'RETIRO_COORDINADOR', 'CASA_EDITORA', NULL, 't-5', 1, 1)",
            "('d-6', 100, 1, 'BANCO', 'CASA_EDITORA', NULL, NULL, 1, 1)",
            "('d-7', 100, 1, 'RETIRO_COORDINADOR', 'ALQUILER', NULL, NULL, 1, 1)",
          ]) {
            await expectLater(nuevo.customStatement('$columnas$malo'), throwsA(anything));
          }
          await nuevo.customStatement(
            "$columnas('d-8', 100, 1, 'RETIRO_COORDINADOR', 'ALQUILER', 'camp-1', NULL, 1, 1)",
          );
          expect(await nuevo.select(nuevo.deposito).get(), hasLength(2));
        },
      );
    },
  );

  test(
    'dado una agenda guardada en la versión 23, cuando migra a la 24, no se pierde nada, suma la '
    'venta y el monto previsto vacíos y deja guardar una cuota (HU-COB-004, #166)',
    () async {
      const agenda = v23.AgendaData(
        id: 'a-1',
        espacioId: 'es-1',
        espacioPersonaId: 'ep-1',
        tipo: 'COBRANZA',
        fechaProgramada: 1,
        esEstricta: 0,
        estado: 'PROGRAMADA',
        colportorId: 'col-1',
        createdAt: 1,
        updatedAt: 1,
        syncVersion: 3,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 23,
        newVersion: 24,
        createOld: v23.DatabaseAtV23.new,
        createNew: v24.DatabaseAtV24.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) {
          batch.insert(viejo.agenda, agenda);
        },
        validateItems: (nuevo) async {
          final citas = await nuevo.select(nuevo.agenda).get();
          expect(citas.map((c) => c.id), ['a-1']);
          expect(citas.single.tipo, 'COBRANZA');
          expect(citas.single.syncVersion, 3);
          expect(citas.single.ventaId, isNull);
          expect(citas.single.montoPrevisto, isNull);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          // Una cobranza con su venta acepta el monto previsto; sin venta, o de otro tipo, no.
          await nuevo.customStatement(
            "UPDATE agenda SET venta_id = 'v-1', monto_previsto = 833 WHERE id = 'a-1'",
          );
          final cuota = await nuevo.select(nuevo.agenda).getSingle();
          expect(cuota.ventaId, 'v-1');
          expect(cuota.montoPrevisto, 833);
          await expectLater(
            nuevo.customStatement("UPDATE agenda SET venta_id = NULL WHERE id = 'a-1'"),
            throwsA(anything),
          );
          await expectLater(
            nuevo.customStatement("UPDATE agenda SET monto_previsto = 0 WHERE id = 'a-1'"),
            throwsA(anything),
          );
          await expectLater(
            nuevo.customStatement("UPDATE agenda SET tipo = 'ENTREVISTA' WHERE id = 'a-1'"),
            throwsA(anything),
          );
        },
      );
    },
  );

  test(
    'dado depósitos guardados en la versión 24, cuando migra a la 25, no se pierde nada, suman la '
    'validación y el rechazo vacíos y no se encola nada (#596)',
    () async {
      // El depósito registrado antes sigue «por validar»: el pull le trae su validación después.
      const deposito = v24.DepositoData(
        id: 'd-1',
        monto: 180000,
        fecha: 1,
        destino: 'BANCO',
        concepto: 'CASA_EDITORA',
        ticketId: 't-1',
        createdAt: 1,
        updatedAt: 1,
        syncVersion: 4,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 24,
        newVersion: 25,
        createOld: v24.DatabaseAtV24.new,
        createNew: v25.DatabaseAtV25.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) => batch.insert(viejo.deposito, deposito),
        validateItems: (nuevo) async {
          final guardado = await nuevo.select(nuevo.deposito).getSingle();
          expect(guardado.id, 'd-1');
          expect(guardado.monto, 180000);
          expect(guardado.ticketId, 't-1');
          expect(guardado.syncVersion, 4);
          expect(guardado.validadoEn, isNull);
          expect(guardado.validadoPor, isNull);
          expect(guardado.rechazadoEn, isNull);
          expect(guardado.motivoRechazo, isNull);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          // Las cuatro columnas aceptan lo que baja del servidor.
          await nuevo.customStatement(
            "UPDATE deposito SET validado_en = 2, validado_por = 'coord-1' WHERE id = 'd-1'",
          );
          final validado = await nuevo.select(nuevo.deposito).getSingle();
          expect(validado.validadoEn, 2);
          expect(validado.validadoPor, 'coord-1');
          await nuevo.customStatement(
            'INSERT INTO deposito (id, monto, fecha, destino, concepto, created_at, updated_at, '
            "rechazado_en, motivo_rechazo) VALUES ('d-2', 500000, 1, 'RETIRO_COORDINADOR', "
            "'CASA_EDITORA', 1, 1, 3, 'Entregaste 5.000, no 6.000')",
          );
          final rechazado = await (nuevo.select(
            nuevo.deposito,
          )..where((d) => d.id.equals('d-2'))).getSingle();
          expect(rechazado.rechazadoEn, 3);
          expect(rechazado.motivoRechazo, 'Entregaste 5.000, no 6.000');
        },
      );
    },
  );

  test('dado devoluciones guardadas en la versión 25, cuando migra a la 26, no se pierde ninguna, '
      'pierden las columnas de dinero y no se encola nada (#609)', () async {
    // Nunca queda plata a favor del cliente: la devolución ya no guarda lo retenido ni lo
    // reembolsado. Cada devolución sigue con sus libros, su motivo, su fecha y su auditoría.
    const libros = '[{"producto_id":"p-1","cantidad":1,"venta_item_id":"i-1"}]';
    const con = v25.DevolucionData(
      id: 'd-1',
      ventaId: 'v-1',
      productosDevueltos: libros,
      dineroRetenido: 190000,
      montoReembolsado: 50000,
      motivo: 'no le gustó',
      fechaDevolucion: 5,
      createdAt: 6,
      updatedAt: 7,
      createdBy: 'col-1',
      syncVersion: 4,
    );
    const sin = v25.DevolucionData(
      id: 'd-2',
      ventaId: 'v-1',
      productosDevueltos: libros,
      dineroRetenido: 0,
      fechaDevolucion: 8,
      createdAt: 8,
      updatedAt: 8,
      deletedAt: 9,
      syncVersion: 0,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 25,
      newVersion: 26,
      createOld: v25.DatabaseAtV25.new,
      createNew: v26.DatabaseAtV26.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch.insert(viejo.devolucion, con);
        batch.insert(viejo.devolucion, sin);
      },
      validateItems: (nuevo) async {
        final filas = await (nuevo.select(
          nuevo.devolucion,
        )..orderBy([(d) => OrderingTerm.asc(d.id)])).get();
        expect(filas.map((d) => d.id), ['d-1', 'd-2']);
        expect(filas.first.ventaId, 'v-1');
        expect(filas.first.productosDevueltos, libros);
        expect(filas.first.motivo, 'no le gustó');
        expect(filas.first.fechaDevolucion, 5);
        expect(filas.first.createdAt, 6);
        expect(filas.first.updatedAt, 7);
        expect(filas.first.createdBy, 'col-1');
        expect(filas.first.syncVersion, 4);
        expect(filas.last.deletedAt, 9);
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

        final columnas = await nuevo.customSelect('PRAGMA table_info(devolucion)').get();
        expect(
          columnas.map((c) => c.read<String>('name')),
          isNot(anyOf(contains('dinero_retenido'), contains('monto_reembolsado'))),
        );
        final indices = await nuevo.customSelect('PRAGMA index_list(devolucion)').get();
        expect(indices.map((i) => i.read<String>('name')), contains('devolucion_venta_idx'));

        // El CHECK del motivo sigue; las filas nuevas no llevan dinero.
        const insertar =
            'INSERT INTO devolucion (id, venta_id, productos_devueltos, motivo, fecha_devolucion, '
            'created_at, updated_at) VALUES ';
        await nuevo.customStatement("$insertar('d-3', 'v-1', '$libros', 'x', 1, 1, 1)");
        for (final malo in [
          "('d-4', 'v-1', '$libros', '', 1, 1, 1)",
          "('d-5', 'v-1', '$libros', '${'a' * 501}', 1, 1, 1)",
        ]) {
          await expectLater(nuevo.customStatement('$insertar$malo'), throwsA(anything));
        }
        expect(await nuevo.select(nuevo.devolucion).get(), hasLength(3));
      },
    );
  });

  test(
    'dado productos guardados en la versión 26, cuando migra a la 27, no se pierde nada, queda sin '
    'categoría hasta el próximo pull y no se encola nada (#561)',
    () async {
      // La categoría baja del servidor (backend-supabase 0149): la fila de antes no se toca ni se deriva
      // de su `tipo`; hasta que el pull la traiga de nuevo, el producto no se ofrece en Precios.
      const producto = v26.ProductoData(
        id: 'pro-1',
        nombre: 'El Conflicto de los Siglos',
        tipo: 'LIBRO',
        esBonificable: 1,
        esMisionero: 0,
        precioBaseCompra: 18000,
        casaEditora: 'ACES',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        syncVersion: 3,
        codigoEditor: 'CS-01',
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 26,
        newVersion: 27,
        createOld: v26.DatabaseAtV26.new,
        createNew: v27.DatabaseAtV27.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) => batch.insert(viejo.producto, producto),
        validateItems: (nuevo) async {
          final guardado = await nuevo.select(nuevo.producto).getSingle();
          expect(guardado.id, 'pro-1');
          expect(guardado.nombre, 'El Conflicto de los Siglos');
          expect(guardado.tipo, 'LIBRO');
          expect(guardado.esBonificable, 1);
          expect(guardado.precioBaseCompra, 18000);
          expect(guardado.codigoEditor, 'CS-01');
          expect(guardado.syncVersion, 3);
          expect(guardado.categoria, isNull);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          // La columna acepta lo que baja del servidor.
          await nuevo.customStatement(
            "UPDATE producto SET categoria = 'ESPIRITUALES' WHERE id = 'pro-1'",
          );
          expect((await nuevo.select(nuevo.producto).getSingle()).categoria, 'ESPIRITUALES');
        },
      );
    },
  );

  test(
    'dado ciudades guardadas en la versión 27, cuando migra a la 28, no se pierde nada, suman el '
    'departamento vacío y no se encola nada (#619)',
    () async {
      // La ciudad que ya estaba sigue ahí: el pull le trae el departamento después.
      const ciudad = v27.CiudadData(
        id: 'ciu-1',
        nombre: 'Montevideo',
        latCentro: -34.9,
        lonCentro: -56.16,
        zoomInicial: 13,
        createdAt: 1,
        updatedAt: 1,
        syncVersion: 4,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 27,
        newVersion: 28,
        createOld: v27.DatabaseAtV27.new,
        createNew: v28.DatabaseAtV28.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) => batch.insert(viejo.ciudad, ciudad),
        validateItems: (nuevo) async {
          final guardada = await nuevo.select(nuevo.ciudad).getSingle();
          expect(guardada.id, 'ciu-1');
          expect(guardada.nombre, 'Montevideo');
          expect(guardada.latCentro, -34.9);
          expect(guardada.syncVersion, 4);
          expect(guardada.departamento, isNull);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          // La columna acepta lo que baja del servidor.
          await nuevo.customStatement(
            "UPDATE ciudad SET departamento = 'San José' WHERE id = 'ciu-1'",
          );
          expect((await nuevo.select(nuevo.ciudad).getSingle()).departamento, 'San José');
        },
      );
    },
  );

  test('dado depósitos guardados en la versión 28, cuando migra a la 29, no se pierde '
      'nada y suma la tabla de la deuda guardada, vacía (#441)', () async {
    const deposito = v28.DepositoData(
      id: 'd-1',
      monto: 180000,
      fecha: 1,
      destino: 'BANCO',
      concepto: 'CASA_EDITORA',
      ticketId: 't-1',
      createdAt: 1,
      updatedAt: 1,
      syncVersion: 4,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 28,
      newVersion: 29,
      createOld: v28.DatabaseAtV28.new,
      createNew: v29.DatabaseAtV29.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) => batch.insert(viejo.deposito, deposito),
      validateItems: (nuevo) async {
        final guardado = await nuevo.select(nuevo.deposito).getSingle();
        expect(guardado.id, 'd-1');
        expect(guardado.monto, 180000);
        expect(guardado.syncVersion, 4);
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

        // La tabla nace vacía, con una fila por colportor: guardar de nuevo la pisa.
        expect(await nuevo.select(nuevo.deudaCasaCache).get(), isEmpty);
        const insertar = 'INSERT INTO deuda_casa_cache (colportor_id, respuesta, leida_en) VALUES ';
        await nuevo.customStatement("$insertar('col-1', '{}', 1)");
        await nuevo.customStatement("$insertar('col-2', '{}', 2)");
        await expectLater(nuevo.customStatement("$insertar('col-1', '{}', 3)"), throwsA(anything));
        expect(await nuevo.select(nuevo.deudaCasaCache).get(), hasLength(2));
      },
    );
  });

  test(
    'dado lo guardado en la versión 29, cuando migra a la 30, no se pierde nada, aparecen los tickets '
    'vacíos con sus CHECK y el cobro gana ticket_id vacío, sin encolar nada',
    () async {
      // HU-COB-007 (#426): `ticket` sube y baja por el motor, `ticket_foto_local` es solo del teléfono y
      // `cobranza.ticket_id` liga el cobro con tarjeta a su ticket.
      const cobro = v29.CobranzaData(
        id: 'c-1',
        ventaId: 'v-1',
        monto: 150000,
        medio: 'TARJETA',
        fecha: 1,
        createdAt: 1,
        updatedAt: 1,
        syncVersion: 4,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 29,
        newVersion: 30,
        createOld: v29.DatabaseAtV29.new,
        createNew: v30.DatabaseAtV30.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) => batch.insert(viejo.cobranza, cobro),
        validateItems: (nuevo) async {
          final c = await nuevo.select(nuevo.cobranza).getSingle();
          expect((c.id, c.monto, c.syncVersion), ('c-1', 150000, 4));
          expect(c.ticketId, isNull);
          expect(await nuevo.select(nuevo.ticket).get(), isEmpty);
          expect(await nuevo.select(nuevo.ticketFotoLocal).get(), isEmpty);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          const columnas =
              'INSERT INTO ticket (id, tipo, monto, fecha, estado, created_at, updated_at) VALUES ';
          await nuevo.customStatement(
            "$columnas('t-1', 'COBRO_TARJETA', 150000, 1, 'PENDIENTE', 1, 1)",
          );
          final ticket = await nuevo.select(nuevo.ticket).getSingle();
          expect(
            (ticket.tipo, ticket.monto, ticket.estado),
            ('COBRO_TARJETA', 150000, 'PENDIENTE'),
          );
          expect(ticket.urlCloud, isNull);
          expect(ticket.usuarioId, isNull);
          expect(ticket.syncVersion, 0);
          for (final malo in [
            "('t-2', 'COBRO_TARJETA', 0, 1, 'PENDIENTE', 1, 1)",
            "('t-3', 'OTRA_COSA', 100, 1, 'PENDIENTE', 1, 1)",
            "('t-4', 'DEPOSITO', 100, 1, 'HECHO', 1, 1)",
          ]) {
            await expectLater(nuevo.customStatement('$columnas$malo'), throwsA(anything));
          }

          const foto =
              'INSERT INTO ticket_foto_local (ticket_id, tipo_de_imagen, bytes, creada_en) VALUES ';
          await nuevo.customStatement("$foto('t-1', 'image/jpeg', 1000, 1)");
          final f = await nuevo.select(nuevo.ticketFotoLocal).getSingle();
          expect((f.estado, f.intentos), ('PENDIENTE', 0));
          expect(f.rutaLocal, isNull);
          await expectLater(
            nuevo.customStatement("$foto('t-2', 'image/jpeg', 0, 1)"),
            throwsA(anything),
          );
        },
      );
    },
  );

  test('dado cobros guardados en la versión 30, cuando migra a la 31, no se pierde ninguno, '
      'pierden numero_cuota y no se encola nada (#608)', () async {
    // El cobro ya no guarda qué número de cuota paga: cada cobro sigue con su venta, su monto, su medio,
    // los datos de la tarjeta y de la transferencia, su ticket y su auditoría; solo desaparece la columna.
    const cuota = v30.CobranzaData(
      id: 'c-1',
      ventaId: 'v-1',
      monto: 50000,
      medio: 'EFECTIVO',
      fecha: 5,
      numeroCuota: 2,
      createdAt: 6,
      updatedAt: 7,
      createdBy: 'col-1',
      syncVersion: 4,
    );
    const tarjeta = v30.CobranzaData(
      id: 'c-2',
      ventaId: 'v-1',
      monto: 30000,
      medio: 'TARJETA',
      fecha: 8,
      tarjetaTipo: 'CREDITO',
      tarjetaMarca: 'OCA',
      numeroAprobacion: 'A-123',
      ticketId: 't-1',
      createdAt: 8,
      updatedAt: 8,
      deletedAt: 9,
      syncVersion: 0,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 30,
      newVersion: 31,
      createOld: v30.DatabaseAtV30.new,
      createNew: v31.DatabaseAtV31.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch.insert(viejo.cobranza, cuota);
        batch.insert(viejo.cobranza, tarjeta);
      },
      validateItems: (nuevo) async {
        final filas = await (nuevo.select(
          nuevo.cobranza,
        )..orderBy([(c) => OrderingTerm.asc(c.id)])).get();
        expect(filas.map((c) => c.id), ['c-1', 'c-2']);
        expect(filas.first.ventaId, 'v-1');
        expect(filas.first.monto, 50000);
        expect(filas.first.medio, 'EFECTIVO');
        expect(filas.first.fecha, 5);
        expect(filas.first.createdAt, 6);
        expect(filas.first.updatedAt, 7);
        expect(filas.first.createdBy, 'col-1');
        expect(filas.first.syncVersion, 4);
        expect(filas.last.tarjetaTipo, 'CREDITO');
        expect(filas.last.tarjetaMarca, 'OCA');
        expect(filas.last.numeroAprobacion, 'A-123');
        expect(filas.last.ticketId, 't-1');
        expect(filas.last.deletedAt, 9);
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

        final columnas = await nuevo.customSelect('PRAGMA table_info(cobranza)').get();
        expect(columnas.map((c) => c.read<String>('name')), isNot(contains('numero_cuota')));
        final indices = await nuevo.customSelect('PRAGMA index_list(cobranza)').get();
        expect(indices.map((i) => i.read<String>('name')), contains('cobranza_venta_idx'));

        // Los CHECK siguen; un cobro nuevo no lleva número de cuota.
        const insertar =
            'INSERT INTO cobranza (id, venta_id, monto, medio, fecha, created_at, updated_at) VALUES ';
        await nuevo.customStatement("$insertar('c-3', 'v-1', 1, 'EFECTIVO', 1, 1, 1)");
        for (final malo in [
          "('c-4', 'v-1', 0, 'EFECTIVO', 1, 1, 1)",
          "('c-5', 'v-1', 1, 'CHEQUE', 1, 1, 1)",
        ]) {
          await expectLater(nuevo.customStatement('$insertar$malo'), throwsA(anything));
        }
        expect(await nuevo.select(nuevo.cobranza).get(), hasLength(3));
      },
    );
  });

  test('dado jornadas guardadas en la versión 31, cuando migra a la 32, no se pierde ninguna, '
      'pierden tipo_acompaniamiento y no se encola nada (#642)', () async {
    // El tipo de acompañamiento se saca del esquema (backend-supabase 0169): cada jornada sigue con su
    // colportor, su inicio y su fin, quién acompaña, sus totales y su auditoría; solo desaparece la columna.
    const abierta = v31.JornadaData(
      id: 'jor-1',
      colportorId: 'col-1',
      inicio: 1758700000000,
      totalVisitas: 0,
      totalVentas: 0,
      createdAt: 1758700000000,
      updatedAt: 1758700000000,
      syncVersion: 0,
    );
    const cerrada = v31.JornadaData(
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
      deletedAt: 1758630000000,
      syncVersion: 4,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 31,
      newVersion: 32,
      createOld: v31.DatabaseAtV31.new,
      createNew: v32.DatabaseAtV32.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch.insert(viejo.jornada, abierta);
        batch.insert(viejo.jornada, cerrada);
      },
      validateItems: (nuevo) async {
        final filas = await (nuevo.select(
          nuevo.jornada,
        )..orderBy([(j) => OrderingTerm.asc(j.id)])).get();
        expect(filas.map((j) => j.id), ['jor-1', 'jor-2']);
        expect(filas.first.fin, isNull);
        expect(filas.first.acompanianteId, isNull);
        expect(filas.first.syncVersion, 0);
        expect(filas.last.colportorId, 'col-1');
        expect(filas.last.inicio, 1758600000000);
        expect(filas.last.fin, 1758620000000);
        expect(filas.last.acompanianteId, 'col-2');
        expect(filas.last.totalVisitas, 12);
        expect(filas.last.totalVentas, 3);
        expect(filas.last.createdBy, 'col-1');
        expect(filas.last.deletedAt, 1758630000000);
        expect(filas.last.syncVersion, 4);
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

        final columnas = await nuevo.customSelect('PRAGMA table_info(jornada)').get();
        expect(
          columnas.map((c) => c.read<String>('name')),
          isNot(contains('tipo_acompaniamiento')),
        );
        final indices = await nuevo.customSelect('PRAGMA index_list(jornada)').get();
        expect(indices.map((i) => i.read<String>('name')), contains('jornada_colportor_idx'));

        // Los CHECK siguen: una jornada que termina antes de empezar no entra.
        const insertar =
            'INSERT INTO jornada (id, colportor_id, inicio, fin, created_at, updated_at) VALUES ';
        await nuevo.customStatement("$insertar('jor-3', 'col-1', 10, 20, 1, 1)");
        await expectLater(
          nuevo.customStatement("$insertar('jor-4', 'col-1', 20, 10, 1, 1)"),
          throwsA(anything),
        );
        expect(await nuevo.select(nuevo.jornada).get(), hasLength(3));
      },
    );
  });

  test('dado lo guardado en la versión 32, cuando migra a la 33, conserva las entregas y las citas '
      '(también las cuotas con su venta y su monto), suma la fecha prevista y deja entrar la cita de '
      'entrega con la entrega que agenda (#433)', () async {
    // HU-VEN-003 (#433): `entrega.fecha_prevista` y, en `agenda`, el tipo ENTREGA con `entrega_id`
    // (`venta_id` y `monto_previsto` ya estaban desde la 24). SQLite no cambia un CHECK: `agenda` se
    // reescribe y no puede perder ninguna fila.
    const entregaPendiente = v32.EntregaData(
      id: 'e-1',
      ventaId: 'v-1',
      productoId: 'p-1',
      cantidad: 2,
      pendiente: 1,
      createdAt: 1758700000000,
      updatedAt: 1758700000000,
      createdBy: 'col-1',
      syncVersion: 1,
    );
    const entregaHecha = v32.EntregaData(
      id: 'e-2',
      ventaId: 'v-1',
      productoId: 'p-2',
      cantidad: 1,
      fechaEntrega: 1758710000000,
      pendiente: 0,
      createdAt: 1758700000000,
      updatedAt: 1758710000000,
      deletedAt: 1758720000000,
      syncVersion: 3,
    );
    const cuota = v32.AgendaData(
      id: 'a-1',
      espacioId: 'esp-1',
      espacioPersonaId: 'ep-1',
      tipo: 'COBRANZA',
      fechaProgramada: 1758700000000,
      esEstricta: 0,
      estado: 'PROGRAMADA',
      colportorId: 'col-1',
      ventaId: 'v-1',
      montoPrevisto: 50000,
      createdAt: 1758700000000,
      updatedAt: 1758700000000,
      createdBy: 'col-1',
      syncVersion: 2,
    );
    const entrevista = v32.AgendaData(
      id: 'a-2',
      espacioId: 'esp-1',
      tipo: 'ENTREVISTA',
      fechaProgramada: 1758800000000,
      slotCodigo: 'mid_morning',
      esEstricta: 1,
      estado: 'CUMPLIDA',
      colportorId: 'col-1',
      visitaId: 'vis-1',
      createdAt: 1758700000000,
      updatedAt: 1758800000000,
      deletedAt: 1758900000000,
      syncVersion: 5,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 32,
      newVersion: 33,
      createOld: v32.DatabaseAtV32.new,
      createNew: v33.DatabaseAtV33.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch.insert(viejo.entrega, entregaPendiente);
        batch.insert(viejo.entrega, entregaHecha);
        batch.insert(viejo.agenda, cuota);
        batch.insert(viejo.agenda, entrevista);
      },
      validateItems: (nuevo) async {
        final entregas = await (nuevo.select(
          nuevo.entrega,
        )..orderBy([(e) => OrderingTerm.asc(e.id)])).get();
        expect(entregas.map((e) => [e.id, e.pendiente, e.fechaPrevista]), [
          ['e-1', 1, null],
          ['e-2', 0, null],
        ]);
        expect(entregas.first.cantidad, 2);
        expect(entregas.first.createdBy, 'col-1');
        expect(entregas.first.syncVersion, 1);
        expect(entregas.last.fechaEntrega, 1758710000000);
        expect(entregas.last.deletedAt, 1758720000000);
        expect(entregas.last.syncVersion, 3);

        final agendas = await (nuevo.select(
          nuevo.agenda,
        )..orderBy([(a) => OrderingTerm.asc(a.id)])).get();
        expect(agendas.map((a) => [a.id, a.tipo, a.ventaId, a.montoPrevisto, a.entregaId]), [
          ['a-1', 'COBRANZA', 'v-1', 50000, null],
          ['a-2', 'ENTREVISTA', null, null, null],
        ]);
        expect(agendas.first.espacioPersonaId, 'ep-1');
        expect(agendas.first.syncVersion, 2);
        expect(agendas.last.slotCodigo, 'mid_morning');
        expect(agendas.last.esEstricta, 1);
        expect(agendas.last.visitaId, 'vis-1');
        expect(agendas.last.deletedAt, 1758900000000);
        expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

        const columnas =
            'INSERT INTO agenda (id, espacio_id, tipo, fecha_programada, es_estricta, estado, '
            'colportor_id, venta_id, entrega_id, monto_previsto, created_at, updated_at) VALUES ';
        // La cita de entrega entra, con la venta y la entrega que la originan.
        await nuevo.customStatement(
          "$columnas('a-3', 'esp-1', 'ENTREGA', 1758800000000, 0, 'PROGRAMADA', 'col-1', 'v-1', "
          "'e-1', NULL, 1, 1)",
        );
        // Otro tipo no entra, una entrega solo cuelga de una cita de entrega, y el monto previsto
        // sigue siendo solo de una cobranza.
        for (final malo in [
          "('a-4', 'esp-1', 'OTRO', 1, 0, 'PROGRAMADA', 'col-1', NULL, NULL, NULL, 1, 1)",
          "('a-5', 'esp-1', 'COBRANZA', 1, 0, 'PROGRAMADA', 'col-1', 'v-1', 'e-1', NULL, 1, 1)",
          "('a-6', 'esp-1', 'ENTREGA', 1, 0, 'PROGRAMADA', 'col-1', 'v-1', 'e-1', 100, 1, 1)",
        ]) {
          await expectLater(nuevo.customStatement('$columnas$malo'), throwsA(anything));
        }
        expect(await nuevo.select(nuevo.agenda).get(), hasLength(3));
        // Los índices de agenda siguen, para la lista de entregas pendientes y la Agenda.
        final indices = await nuevo
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
            .get();
        expect(
          indices.map((r) => r.read<String>('name')),
          containsAll([
            'agenda_venta_idx',
            'agenda_colportor_idx',
            'agenda_espacio_idx',
            'agenda_espacio_persona_idx',
          ]),
        );
      },
    );
  });

  test(
    'dado visitas guardadas en la versión 33, cuando migra a la 34, no se pierde ninguna, quedan '
    'sin horas de entrevista y aparece visita_misionero vacía (#466, #608)',
    () async {
      const visita = v33.VisitaData(
        id: 'vis-1',
        espacioId: 'esp-1',
        espacioPersonaId: 'ep-1',
        fecha: 1758700000000,
        tipoResultado: 'ENTREVISTA',
        colportorId: 'col-1',
        jornadaId: 'jor-1',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        createdBy: 'col-1',
        syncVersion: 2,
      );
      const borrada = v33.VisitaData(
        id: 'vis-2',
        espacioId: 'esp-1',
        fecha: 1758800000000,
        tipoResultado: 'RECHAZO',
        colportorId: 'col-1',
        createdAt: 1758800000000,
        updatedAt: 1758900000000,
        deletedAt: 1758900000000,
        syncVersion: 4,
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 33,
        newVersion: 34,
        createOld: v33.DatabaseAtV33.new,
        createNew: v34.DatabaseAtV34.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) {
          batch.insert(viejo.visita, visita);
          batch.insert(viejo.visita, borrada);
        },
        validateItems: (nuevo) async {
          final visitas = await (nuevo.select(
            nuevo.visita,
          )..orderBy([(v) => OrderingTerm.asc(v.id)])).get();
          expect(
            visitas.map(
              (v) => [v.id, v.tipoResultado, v.jornadaId, v.entrevistaEntrada, v.entrevistaSalida],
            ),
            [
              ['vis-1', 'ENTREVISTA', 'jor-1', null, null],
              ['vis-2', 'RECHAZO', null, null, null],
            ],
          );
          expect(visitas.first.espacioPersonaId, 'ep-1');
          expect(visitas.first.syncVersion, 2);
          expect(visitas.last.deletedAt, 1758900000000);
          expect(await nuevo.select(nuevo.visitaMisionero).get(), isEmpty);
          expect(await nuevo.select(nuevo.syncQueue).get(), isEmpty);

          const columnas =
              'INSERT INTO visita_misionero (id, visita_id, producto_id, cantidad, created_at, '
              'updated_at) VALUES ';
          await nuevo.customStatement("$columnas('vm-1', 'vis-1', 'p-1', 2, 1, 1)");
          // Sin cantidad no hay misionero dejado.
          await expectLater(
            nuevo.customStatement("$columnas('vm-2', 'vis-1', 'p-2', 0, 1, 1)"),
            throwsA(anything),
          );
          final indices = await nuevo
              .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
              .get();
          expect(
            indices.map((r) => r.read<String>('name')),
            contains('visita_misionero_visita_idx'),
          );
        },
      );
    },
  );

  test('dado la cola del motor en la versión 34, cuando migra a la 35, conserva cada job con su '
      'estado, su lugar y su payload, y deja entrar la unión de duplicados (#679)', () async {
    // contrato-sync-engine §6.2: `sync_queue.op` suma `marcar_como_duplicado`. SQLite no cambia un
    // CHECK: la tabla se reescribe y no puede perder ningún job (son ventas que esperan subir).
    const alta = v34.SyncQueueData(
      id: 'q-1',
      clientOpId: 'op-1',
      entity: 'ubicacion',
      op: 'insert',
      payload: '{"id":"ub-a"}',
      rowPk: 'ub-a',
      createdAt: 1758700000000,
      state: 'PENDING',
      code: '',
      message: '',
    );
    const enEspera = v34.SyncQueueData(
      id: 'q-2',
      clientOpId: 'op-2',
      entity: 'espacio',
      op: 'update',
      payload: '{"id":"esp-1","ubicacion_id":"ub-a"}',
      syncVersion: 3,
      rowPk: 'esp-1',
      createdAt: 1758700000001,
      state: 'WAITING',
      code: 'ESPERA_ALTA_EN_CONFLICTO',
      message: 'espera el alta',
      dependsOn: 'ub-a',
      claimedAt: 1758700000500,
    );
    const hecho = v34.SyncQueueData(
      id: 'q-3',
      clientOpId: 'op-3',
      entity: 'venta',
      op: 'delete',
      payload: '{"id":"v-1"}',
      syncVersion: 1,
      rowPk: 'v-1',
      createdAt: 1758700000002,
      state: 'DONE',
      code: '',
      message: '',
      doneAt: 1758700001000,
    );

    await verificador.testWithDataIntegrity(
      oldVersion: 34,
      newVersion: 35,
      createOld: v34.DatabaseAtV34.new,
      createNew: v35.DatabaseAtV35.new,
      openTestedDatabase: _abrir,
      createItems: (batch, viejo) {
        batch.insertAll(viejo.syncQueue, [alta, enEspera, hecho]);
      },
      validateItems: (nuevo) async {
        final jobs = await (nuevo.select(
          nuevo.syncQueue,
        )..orderBy([(q) => OrderingTerm.asc(q.createdAt)])).get();
        expect(jobs.map((q) => q.toJson()), [
          for (final q in [alta, enEspera, hecho]) q.toJson(),
        ]);

        const insertar =
            'INSERT INTO sync_queue (id, client_op_id, entity, op, payload, row_pk, created_at, '
            'state) VALUES ';
        await nuevo.customStatement(
          "$insertar('q-4', 'op-4', 'ubicacion', 'marcar_como_duplicado', "
          "'{\"duplicada_id\":\"ub-b\",\"conservada_id\":\"ub-a\"}', 'ub-b', 1758700000003, "
          "'PENDING')",
        );
        await expectLater(
          nuevo.customStatement(
            "$insertar('q-5', 'op-5', 'ubicacion', 'upsert', '{}', 'ub-b', 1758700000004, "
            "'PENDING')",
          ),
          throwsA(anything),
          reason: 'el CHECK sigue rechazando un op que el motor no conoce',
        );
        expect(await nuevo.select(nuevo.syncQueue).get(), hasLength(4));
      },
    );
  });
}

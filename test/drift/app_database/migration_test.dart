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
import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v11.dart' as v11;
import 'generated/schema_v12.dart' as v12;
import 'generated/schema_v13.dart' as v13;
import 'generated/schema_v14.dart' as v14;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
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

  test('dado lo guardado en la versión 13, cuando migra a la 14, no se pierde nada y aparecen la venta '
      'y sus ítems vacíos, con los CHECK del servidor y sin encolar nada', () async {
    // HU-VEN-001 (#423): `venta` y `venta_item` suben por el motor; al migrar solo se crean.
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
}

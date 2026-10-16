// Lo que baja del servidor entra a las tablas de negocio por `DriftLocalStore`, columna por
// columna y por nombre. La prueba de que eso está bien es la identidad: la fila del cloud
// (`Modelo.toJson()`, la forma con la que viaja) aplicada por `applyDelta` se lee igual que el
// modelo, con los mismos DAOs y conversores que usa la app.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/zona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/models/campania_ciudad_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/zona_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/zona_vertice_model.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/port_contracts.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../helpers/logger_mudo.dart';

const _ubicacion = {
  'id': '01920000-0000-7000-8000-0000000000u1',
  'tipo': 'CASA',
  'calle': 'Av. Ñandú',
  'numero': '1234 bis',
  'lat': -34.9012345,
  'lon': -56.16,
  'ciudad_id': 'ciu-1',
  'zona_id': 'zon-1',
  'created_at': '2026-10-16T12:00:00.000Z',
  'updated_at': '2026-10-16T12:30:00.000Z',
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 4,
  // Columnas que el servidor manda y la tabla local no tiene: se ignoran.
  'xmin_w': '123456',
};

const _jornada = {
  'id': 'jor-1',
  'colportor_id': 'col-1',
  'inicio': '2026-10-16T08:00:00.000Z',
  'fin': null,
  'acompaniante_id': null,
  'tipo_acompaniamiento': null,
  'total_visitas': 7,
  'total_ventas': 2,
  'created_at': '2026-10-16T08:00:00.000Z',
  'updated_at': '2026-10-16T08:00:00.000Z',
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 1,
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftLocalStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
  });
  tearDown(() => db.close());

  final abiertas = <AppDatabase>[];
  tearDown(() async {
    for (final d in abiertas) {
      await d.close();
    }
    abiertas.clear();
  });
  runLocalStoreContract('DriftLocalStore', () {
    final d = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    abiertas.add(d);
    return DriftLocalStore(d, entidades: entidadesQueEscribeElMotor);
  }, fila: (entidad: 'jornada', fila: _jornada));

  group('la fila del cloud se lee como el modelo', () {
    test('ubicacion: fechas ISO a epoch ms, acentos y decimales', () async {
      await store.applyDelta(
        {
          'ubicacion': [_ubicacion],
        },
        scope: 'mirror',
        watermark: 'w1',
      );

      final dao = UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
      final leida = await dao.obtener(_ubicacion['id']! as String);
      expect(leida!.toJson(), {..._ubicacion}..remove('xmin_w'));
    });

    test('jornada', () async {
      await store.applyDelta(
        {
          'jornada': [_jornada],
        },
        scope: 'mirror',
        watermark: 'w1',
      );

      final dao = JornadaLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
      final activa = await dao.obtenerActiva('col-1');
      expect(activa!.toJson(), _jornada);
    });

    test('el mapa de la campaña: campania_ciudad, zona con su GeoJSON y vértices', () async {
      final cc = {
        'id': 'cc-1',
        'campania_id': 'cam-1',
        'ciudad_id': 'ciu-1',
        'created_at': '2026-10-01T00:00:00.000Z',
        'updated_at': '2026-10-01T00:00:00.000Z',
        'created_by': null,
        'deleted_at': null,
        'sync_version': 1,
      };
      final zona = {
        'id': 'zon-1',
        'nombre': 'Centro',
        'campania_ciudad_id': 'cc-1',
        'tipo_forma': 'ESQUINAS',
        'centro_lat': null,
        'centro_lon': null,
        'radio_m': null,
        'poligono_geojson': {
          'type': 'Polygon',
          'coordinates': [
            [
              [-56.2, -34.9],
              [-56.1, -34.9],
              [-56.1, -34.8],
              [-56.2, -34.9],
            ],
          ],
        },
        'color': '#3366FF',
        'created_at': '2026-10-01T00:00:00.000Z',
        'updated_at': '2026-10-02T00:00:00.000Z',
        'created_by': 'coord-1',
        'deleted_at': null,
        'sync_version': 3,
      };

      await store.applyDelta(
        {
          'campania_ciudad': [cc],
          'zona': [zona],
        },
        scope: 'catalogo',
        watermark: 'w1',
      );

      final [vigente] = await ZonaLocalDataSourceDrift(db).vivasDeCiudad('ciu-1');
      expect(vigente.zona, ZonaModel.fromJson(zona));
      expect(vigente.campaniaId, 'cam-1');
      final fila = await db.select(db.campaniasCiudad).getSingle();
      expect(CampaniaCiudadModel.fromFila(fila), CampaniaCiudadModel.fromJson(cc));
    });

    test('zona_vertice', () async {
      final vertice = {
        'id': 'v-1',
        'zona_id': 'zon-1',
        'orden': 0,
        'lat': -34.9,
        'lon': -56.2,
        'calle_a': 'Rivera',
        'calle_b': 'Bulevar Artigas',
        'created_at': '2026-10-01T00:00:00.000Z',
        'updated_at': '2026-10-01T00:00:00.000Z',
        'created_by': null,
        'deleted_at': null,
        'sync_version': 1,
      };
      await store.applyDelta(
        {
          'zona_vertice': [vertice],
        },
        scope: 'catalogo',
        watermark: 'w1',
      );

      final fila = await db.select(db.zonaVertices).getSingle();
      expect(ZonaVerticeModel.fromFila(fila), ZonaVerticeModel.fromJson(vertice));
    });
  });

  test('la server_row de un LWW pisa la fila local (§5.4)', () async {
    await store.applyDelta(
      {
        'ubicacion': [_ubicacion],
      },
      scope: 'mirror',
      watermark: 'w1',
    );

    await store.applyDelta(
      {
        'ubicacion': [
          {..._ubicacion, 'calle': 'Rivera', 'sync_version': 5},
        ],
      },
      scope: 'mirror',
      watermark: 'w1',
    );

    final dao = UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
    final leida = await dao.obtener(_ubicacion['id']! as String);
    expect(leida!.calle, 'Rivera');
    expect(leida.auditoria.syncVersion, 5);
  });

  test(
    'applyVersions le pone a cada fila la versión del servidor y saltea la que no está',
    () async {
      await store.applyDelta(
        {
          'jornada': [_jornada],
        },
        scope: 'mirror',
        watermark: 'w1',
      );

      await store.applyVersions(
        'jornada',
        pkColumn: 'id',
        versionPorFila: {'jor-1': 2, 'jor-x': 9},
      );

      final fila = await db.select(db.jornadas).getSingle();
      expect(fila.syncVersion, 2);
    },
  );

  group('solo escribe en las entidades del sync', () {
    for (final ajena in ['audit_log', 'sesion_usuario', 'sync_queue', 'no_existe']) {
      test('$ajena: falla y el watermark no avanza', () async {
        await expectLater(
          store.applyDelta(
            {
              ajena: [
                {'id': 'x'},
              ],
            },
            scope: 'mirror',
            watermark: 'w2',
          ),
          throwsArgumentError,
        );
        expect(await store.watermarkOf('mirror'), isNull);
      });
    }
  });

  test('una fila que falla revierte el delta entero y el watermark', () async {
    await expectLater(
      store.applyDelta(
        {
          'ubicacion': [
            _ubicacion,
            {..._ubicacion, 'id': 'otra', 'created_at': 'no es una fecha'},
          ],
        },
        scope: 'mirror',
        watermark: 'w2',
      ),
      throwsFormatException,
    );

    expect(await db.select(db.ubicaciones).get(), isEmpty);
    expect(await store.watermarkOf('mirror'), isNull);
  });

  test('el registro de la app cubre cada tabla de la DB local', () {
    // Una tabla nueva sin declarar en `catalogo.dart` revienta acá y al arrancar el motor: con
    // datos personales, olvidarse no puede ser silencioso.
    expect(() => registroDeLaApp(db.allTables.map((t) => t.actualTableName)), returnsNormally);
  });

  group('réplicas del catálogo', () {
    test('booleanos, enteros y fechas de calendario llegan con su tipo', () async {
      await store.applyDelta(
        {
          'producto': [
            {
              'id': 'pro-1',
              'nombre': 'El Deseado de todas las gentes',
              'descripcion': null,
              'tipo': 'LIBRO',
              'es_bonificable': true,
              'es_misionero': false,
              'precio_base_compra': 450,
              'casa_editora': 'ACES',
              'imagen_url': null,
              'created_at': '2026-10-16T12:00:00.000Z',
              'updated_at': '2026-10-16T12:00:00.000Z',
              'created_by': null,
              'deleted_at': null,
              'sync_version': 2,
              'xmin_w': '99',
            },
          ],
          'precio_por_ciudad': [
            {
              'id': 'pre-1',
              'campania_ciudad_id': 'cc-1',
              'producto_id': 'pro-1',
              'coleccion_id': null,
              'precio_venta': 1200,
              'valido_desde': '2026-12-01',
              'valido_hasta': null,
              'created_at': '2026-10-16T12:00:00.000Z',
              'updated_at': '2026-10-16T12:00:00.000Z',
              'created_by': null,
              'deleted_at': null,
              'sync_version': 1,
            },
          ],
        },
        scope: 'replica',
        watermark: 'w1',
      );

      final producto = await db.select(db.replicaProductos).getSingle();
      expect(producto.esBonificable, isTrue);
      expect(producto.esMisionero, isFalse);
      expect(producto.precioBaseCompra, 450);
      expect(producto.createdAt, DateTime.utc(2026, 10, 16, 12));
      final precio = await db.select(db.replicaPreciosPorCiudad).getSingle();
      expect(precio.validoDesde, '2026-12-01');
      expect(precio.precioVenta, 1200);
    });
  });

  group('fuera del área (§2.1): se marca, nunca se borra', () {
    Map<String, Object?> ubi(String id) => {..._ubicacion, 'id': id};

    Future<void> tener(List<String> ids) =>
        store.applyDelta({'ubicacion': ids.map(ubi).toList()}, scope: 'replica', watermark: 'w0');

    test('out_of_area la marca y la app la ve', () async {
      await tener(['u1', 'u2']);

      await store.applyDelta(
        const {},
        scope: 'replica',
        watermark: 'w1',
        notices: const PullNotices(
          outOfArea: {
            'ubicacion': ['u1'],
          },
        ),
      );

      expect(await store.observarFueraDelArea('ubicacion').first, {'u1'});
      expect(await db.select(db.ubicaciones).get(), hasLength(2), reason: 'nada se borra');
    });

    test('la que vuelve a bajar deja de estar afuera', () async {
      await tener(['u1']);
      await store.applyDelta(
        const {},
        scope: 'replica',
        watermark: 'w1',
        notices: const PullNotices(
          outOfArea: {
            'ubicacion': ['u1'],
          },
        ),
      );

      await tener(['u1']);

      expect(await store.observarFueraDelArea('ubicacion').first, isEmpty);
    });

    test('area_reset: lo que no vuelve a bajar queda afuera recién en la última página, '
        'y lo que tiene escrituras sin subir no cuenta', () async {
      await tener(['u1', 'u2', 'u3', 'u4']);
      // u4 tiene una corrección en la cola que todavía no subió.
      await DriftJobStore(db).append(
        SyncJob(
          clientOpId: 'op-u4',
          entity: 'ubicacion',
          op: Op.update,
          payload: ubi('u4'),
          createdAt: DateTime.utc(2026, 10, 16),
          rowPk: 'u4',
        ),
      );

      await store.applyDelta(
        {
          'ubicacion': [ubi('u2')],
        },
        scope: 'replica',
        watermark: 'r1',
        notices: const PullNotices(areaReset: {'ubicacion'}, complete: false),
      );
      expect(
        await store.observarFueraDelArea('ubicacion').first,
        isEmpty,
        reason: 'a mitad de la descarga no se sabe qué quedó afuera',
      );

      // El LWW de un push, en el medio, no concluye nada.
      await store.applyDelta(
        {
          'ubicacion': [ubi('u9')],
        },
        scope: 'mirror',
        watermark: '',
      );

      await store.applyDelta(
        {
          'ubicacion': [ubi('u3')],
        },
        scope: 'replica',
        watermark: 'r2',
        notices: const PullNotices(),
      );

      expect(await store.observarFueraDelArea('ubicacion').first, {'u1'});
      expect(await db.select(db.ubicaciones).get(), hasLength(5));
    });
  });
}

// La réplica local del catálogo de ventas (HU-CAT-007, #180). Lo que baja el pull entra por
// `DriftLocalStore`, columna por columna y por nombre, así que la prueba de que las tablas tienen
// la forma del cloud es doble: toda columna local existe en la fila del servidor, y la fila
// aplicada se lee igual que como viajó.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/logger_mudo.dart';

/// Las filas como las arma `sync.pull` (backend-supabase 0002): todas las columnas de la tabla, los
/// `timestamptz` en ISO-8601 con zona, los `date` como `AAAA-MM-DD` y `xmin_w` de más.
const _producto = {
  'id': 'pro-1',
  'nombre': 'El Conflicto de los Siglos',
  'descripcion': 'Edición de bolsillo',
  'tipo': 'LIBRO',
  'es_bonificable': true,
  'es_misionero': false,
  'precio_base_compra': 18000,
  'casa_editora': 'ACES',
  'imagen_url': 'https://cdn.ejemplo.uy/conflicto.jpg',
  'created_at': '2026-10-20T12:00:00.123456+00:00',
  'updated_at': '2026-10-21T09:30:00+00:00',
  'created_by': 'adm-1',
  'deleted_at': null,
  'sync_version': 3,
  'codigo_editor': 'CS-01',
  'xmin_w': '123456',
};

const _coleccion = {
  'id': 'col-1',
  'nombre': 'Pack Familiar',
  'libros_a_elegir': 2,
  'created_at': '2026-10-20T12:00:00+00:00',
  'updated_at': '2026-10-20T12:00:00+00:00',
  'created_by': null,
  'deleted_at': null,
  'sync_version': 1,
  'xmin_w': '123457',
};

const _componente = {
  'id': 'pc-1',
  'producto_id': 'pro-1',
  'coleccion_id': 'col-1',
  'cantidad': 2,
  'created_at': '2026-10-20T12:00:00+00:00',
  'updated_at': '2026-10-20T12:00:00+00:00',
  'created_by': null,
  'deleted_at': null,
  'sync_version': 1,
  'xmin_w': '123458',
};

const _excepcion = {
  'id': 'ppc-1',
  'producto_id': 'pro-1',
  'coleccion_id': null,
  'campania_ciudad_id': 'cc-1',
  'precio_venta': 42000,
  'valido_desde': '2026-10-27',
  'valido_hasta': null,
  'created_at': '2026-10-27T03:00:00+00:00',
  'updated_at': '2026-10-27T03:00:00+00:00',
  'created_by': 'coord-1',
  'deleted_at': null,
  'sync_version': 2,
  'xmin_w': '123459',
};

const _general = {
  'id': 'pg-1',
  'producto_id': null,
  'coleccion_id': 'col-1',
  'precio_venta': 120000,
  'valido_desde': '2026-01-01',
  'valido_hasta': '2026-12-31',
  'created_at': '2026-10-15T15:00:00+00:00',
  'updated_at': '2026-10-15T15:00:00+00:00',
  'created_by': 'adm-1',
  'deleted_at': null,
  'sync_version': 1,
  'xmin_w': '123460',
};

/// El parámetro sembrado por backend-supabase 0070: los días del aviso fuerte de precios viejos.
const _parametro = {
  'id': 'par-1',
  'clave': 'dias_antiguedad_precios',
  'valor': 15,
  'created_at': '2026-10-27T23:00:00+00:00',
  'updated_at': '2026-10-27T23:00:00+00:00',
  'created_by': null,
  'deleted_at': null,
  'sync_version': 1,
  'xmin_w': '123461',
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

  Future<void> aplicar(Map<String, List<Map<String, Object?>>> filas, {String w = 'w1'}) =>
      store.applyDelta(filas, scope: 'replica', watermark: w);

  group('cada tabla tiene la forma de la entidad del cloud', () {
    final porEntidad = <String, Map<String, Object?>>{
      'producto': _producto,
      'coleccion': _coleccion,
      'producto_coleccion': _componente,
      'precio_por_ciudad': _excepcion,
      'precio_general': _general,
      'parametro_global': _parametro,
    };

    for (final MapEntry(key: entidad, value: fila) in porEntidad.entries) {
      test('$entidad: toda columna local viene en la fila del servidor', () {
        final tabla = db.allTables.singleWhere((t) => t.actualTableName == entidad);
        final locales = tabla.$columns.map((c) => c.name).toSet();
        expect(fila.keys.toSet().containsAll(locales), isTrue, reason: '$entidad: faltan columnas');
        // Lo único que el servidor manda de más es `xmin_w`, el cursor del delta: no se guarda.
        expect(fila.keys.toSet().difference(locales), {'xmin_w'});
      });
    }

    test('producto: textos, booleanos, centavos y fechas ISO a epoch ms UTC', () async {
      await aplicar({
        'producto': [_producto],
      });

      final p = await db.select(db.productos).getSingle();
      expect(p.id, 'pro-1');
      expect(p.nombre, 'El Conflicto de los Siglos');
      expect(p.descripcion, 'Edición de bolsillo');
      expect(p.tipo, 'LIBRO');
      expect(p.esBonificable, isTrue);
      expect(p.esMisionero, isFalse);
      expect(p.precioBaseCompra, 18000);
      expect(p.casaEditora, 'ACES');
      expect(p.imagenUrl, 'https://cdn.ejemplo.uy/conflicto.jpg');
      expect(p.createdAt, DateTime.utc(2026, 10, 20, 12, 0, 0, 123));
      expect(p.updatedAt, DateTime.utc(2026, 10, 21, 9, 30));
      expect(p.createdBy, 'adm-1');
      expect(p.deletedAt, isNull);
      expect(p.syncVersion, 3);
      expect(p.codigoEditor, 'CS-01');
    });

    test('producto: los opcionales llegan en null', () async {
      await aplicar({
        'producto': [
          {
            ..._producto,
            'descripcion': null,
            'precio_base_compra': null,
            'casa_editora': null,
            'imagen_url': null,
            'created_by': null,
            'codigo_editor': null,
          },
        ],
      });

      final p = await db.select(db.productos).getSingle();
      expect([
        p.descripcion,
        p.precioBaseCompra,
        p.casaEditora,
        p.imagenUrl,
        p.createdBy,
        p.codigoEditor,
      ], everyElement(isNull));
    });

    test(
      'producto: un servidor sin la columna nueva (sin codigo_editor) igual se aplica',
      () async {
        // El delta de un servidor que todavía no corrió backend-supabase 0070 no trae la columna.
        final sinCodigo = {..._producto}..remove('codigo_editor');

        await aplicar({
          'producto': [sinCodigo],
        });

        expect((await db.select(db.productos).getSingle()).codigoEditor, isNull);
      },
    );

    test('parametro_global: la clave y su valor entero, con las fechas a epoch ms UTC', () async {
      await aplicar({
        'parametro_global': [_parametro],
      });

      final p = await db.select(db.parametrosGlobales).getSingle();
      expect([p.id, p.clave, p.valor], ['par-1', 'dias_antiguedad_precios', 15]);
      expect(p.createdAt, DateTime.utc(2026, 10, 27, 23));
      expect(p.deletedAt, isNull);
      expect(p.syncVersion, 1);
    });

    test(
      'coleccion y producto_coleccion: el combo con sus libros a elegir y sus cantidades',
      () async {
        await aplicar({
          'coleccion': [_coleccion],
          'producto_coleccion': [_componente],
        });

        final c = await db.select(db.colecciones).getSingle();
        expect([c.id, c.nombre, c.librosAElegir], ['col-1', 'Pack Familiar', 2]);
        final pc = await db.select(db.productoColecciones).getSingle();
        expect([pc.productoId, pc.coleccionId, pc.cantidad], ['pro-1', 'col-1', 2]);
      },
    );

    test('precio_por_ciudad: la vigencia queda como llegó, sin correrse un día', () async {
      await aplicar({
        'precio_por_ciudad': [_excepcion],
      });

      final p = await db.select(db.preciosPorCiudad).getSingle();
      expect(p.productoId, 'pro-1');
      expect(p.coleccionId, isNull);
      expect(p.campaniaCiudadId, 'cc-1');
      expect(p.precioVenta, 42000);
      // `date` del cloud: texto `AAAA-MM-DD`, nunca un instante (que cambiaría según la zona).
      expect(p.validoDesde, '2026-10-27');
      expect(p.validoHasta, isNull);
    });

    test('precio_general: el precio de un combo para todo el país, con su vigencia', () async {
      await aplicar({
        'precio_general': [_general],
      });

      final g = await db.select(db.preciosGenerales).getSingle();
      expect(g.productoId, isNull);
      expect(g.coleccionId, 'col-1');
      expect(g.precioVenta, 120000);
      expect([g.validoDesde, g.validoHasta], ['2026-01-01', '2026-12-31']);
    });
  });

  group('el delta siguiente pisa la fila, nunca la duplica', () {
    test('un precio que cambia queda con el importe y la versión nuevos', () async {
      await aplicar({
        'precio_por_ciudad': [_excepcion],
      });

      await aplicar({
        'precio_por_ciudad': [
          {..._excepcion, 'precio_venta': 45000, 'sync_version': 3},
        ],
      }, w: 'w2');

      final filas = await db.select(db.preciosPorCiudad).get();
      expect(filas, hasLength(1));
      expect([filas.single.precioVenta, filas.single.syncVersion], [45000, 3]);
      expect(await store.watermarkOf('replica'), 'w2');
    });

    test('una baja (soft delete) llega como fecha y la fila se conserva', () async {
      await aplicar({
        'precio_por_ciudad': [_excepcion],
        'producto': [_producto],
      });

      await aplicar({
        'precio_por_ciudad': [
          {..._excepcion, 'deleted_at': '2026-10-28T10:00:00+00:00', 'sync_version': 3},
        ],
        'producto': [
          {..._producto, 'deleted_at': '2026-10-28T10:00:00+00:00', 'sync_version': 4},
        ],
      }, w: 'w2');

      final precio = await db.select(db.preciosPorCiudad).getSingle();
      expect(precio.deletedAt, DateTime.utc(2026, 10, 28, 10));
      final producto = await db.select(db.productos).getSingle();
      expect(producto.deletedAt, DateTime.utc(2026, 10, 28, 10));
    });

    test(
      'un parámetro que Administración cambia queda con el valor nuevo, en la misma fila',
      () async {
        await aplicar({
          'parametro_global': [_parametro],
        });

        await aplicar({
          'parametro_global': [
            {..._parametro, 'valor': 30, 'sync_version': 2},
          ],
        }, w: 'w2');

        final filas = await db.select(db.parametrosGlobales).get();
        expect(filas, hasLength(1));
        expect([filas.single.valor, filas.single.syncVersion], [30, 2]);
      },
    );
  });

  test(
    'un delta con una fila que la tabla rechaza no aplica nada y el watermark no avanza',
    () async {
      await aplicar({
        'producto': [_producto],
      });

      // El combo trae un componente con cantidad 0: la tabla lo rechaza (como el servidor), y el
      // producto nuevo del mismo delta no puede quedar a medias.
      await expectLater(
        aplicar({
          'producto': [
            {..._producto, 'id': 'pro-2', 'nombre': 'Otro'},
          ],
          'producto_coleccion': [
            {..._componente, 'cantidad': 0},
          ],
        }, w: 'w2'),
        throwsA(anything),
      );

      expect(await db.select(db.productos).get(), hasLength(1));
      expect(await db.select(db.productoColecciones).get(), isEmpty);
      expect(await store.watermarkOf('replica'), 'w1');
    },
  );

  test(
    'una fila de un producto o un combo a la vez: sin ninguno de los dos, la tabla la rechaza',
    () async {
      await expectLater(
        aplicar({
          'precio_general': [
            {..._general, 'producto_id': null, 'coleccion_id': null},
          ],
        }),
        throwsA(anything),
      );

      expect(await db.select(db.preciosGenerales).get(), isEmpty);
    },
  );
}

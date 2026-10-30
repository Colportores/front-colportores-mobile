// Los precios en el teléfono (HU-CAT-006, #419): el catálogo que bajó el pull, leído de la DB local y
// resuelto por ciudad con el `ResolvedorDePrecios`, sin conexión. Las filas entran como las arma
// `sync.pull`, por el mismo `DriftLocalStore` del motor, así que lo que se prueba es el camino real.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/catalogo/data/datasources/catalogo_local_data_source.dart';
import 'package:colportores_mobile/features/catalogo/data/repositories/consulta_de_precios_repository_impl.dart';
import 'package:colportores_mobile/features/catalogo/data/repositories/dias_de_antiguedad_de_precios_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/item_de_precio.dart';
import 'package:colportores_mobile/features/catalogo/domain/services/antiguedad_de_precios.dart';
import 'package:colportores_mobile/features/catalogo/domain/services/resolvedor_de_precios.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/logger_mudo.dart';

const _hoy = '2026-10-28';
const _rivera = 'cc-rivera';
const _montevideo = 'cc-montevideo';

const _fecha = '2026-10-20T12:00:00+00:00';

Map<String, Object?> _producto(
  String id,
  String nombre, {
  String tipo = 'LIBRO',
  bool bonificable = false,
  bool misionero = false,
  String? codigo,
  bool baja = false,
}) => {
  'id': id,
  'nombre': nombre,
  'descripcion': null,
  'tipo': tipo,
  'es_bonificable': bonificable,
  'es_misionero': misionero,
  'precio_base_compra': null,
  'casa_editora': null,
  'imagen_url': null,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': baja ? '2026-10-27T10:00:00+00:00' : null,
  'sync_version': 1,
  'codigo_editor': codigo,
};

Map<String, Object?> _combo(String id, String nombre, {int aElegir = 0, bool baja = false}) => {
  'id': id,
  'nombre': nombre,
  'libros_a_elegir': aElegir,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': baja ? '2026-10-27T10:00:00+00:00' : null,
  'sync_version': 1,
};

Map<String, Object?> _componente(
  String id,
  String productoId,
  String comboId, {
  int cantidad = 1,
  bool baja = false,
}) => {
  'id': id,
  'producto_id': productoId,
  'coleccion_id': comboId,
  'cantidad': cantidad,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': baja ? '2026-10-27T10:00:00+00:00' : null,
  'sync_version': 1,
};

Map<String, Object?> _excepcion(
  String id,
  String ciudad,
  int centavos, {
  String? producto,
  String? combo,
  String desde = '2026-01-01',
  String? hasta,
  bool baja = false,
}) => {
  'id': id,
  'producto_id': producto,
  'coleccion_id': combo,
  'campania_ciudad_id': ciudad,
  'precio_venta': centavos,
  'valido_desde': desde,
  'valido_hasta': hasta,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': baja ? '2026-10-27T10:00:00+00:00' : null,
  'sync_version': 1,
};

Map<String, Object?> _general(
  String id,
  int centavos, {
  String? producto,
  String? combo,
  String desde = '2026-01-01',
  String? hasta,
  bool baja = false,
}) => {
  'id': id,
  'producto_id': producto,
  'coleccion_id': combo,
  'precio_venta': centavos,
  'valido_desde': desde,
  'valido_hasta': hasta,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': baja ? '2026-10-27T10:00:00+00:00' : null,
  'sync_version': 1,
};

Map<String, Object?> _parametro(
  int valor, {
  String id = 'par-1',
  String clave = 'dias_antiguedad_precios',
  String actualizado = _fecha,
  bool baja = false,
}) => {
  'id': id,
  'clave': clave,
  'valor': valor,
  'created_at': _fecha,
  'updated_at': actualizado,
  'created_by': null,
  'deleted_at': baja ? '2026-10-27T10:00:00+00:00' : null,
  'sync_version': 1,
};

/// Un [CatalogoLocalDataSource] que no puede leer, como una DB que falla.
class _DatosRotos extends CatalogoLocalDataSource {
  _DatosRotos(super.db);

  @override
  Stream<CatalogoLocal> observar(String campaniaCiudadId) => Stream.error(StateError('disco roto'));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftLocalStore store;
  late CatalogoLocalDataSource datos;
  var marca = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
    datos = CatalogoLocalDataSource(db);
    marca = 0;
  });
  tearDown(() => db.close());

  Future<void> bajar(Map<String, List<Map<String, Object?>>> filas) =>
      store.applyDelta(filas, scope: 'replica', watermark: 'w${++marca}');

  Future<List<ItemDePrecio>> precios(String ciudad) async =>
      ResolvedorDePrecios.resolver(await datos.leer(ciudad), dia: _hoy);

  PrecioDeProducto producto(List<ItemDePrecio> items, String nombre) =>
      items.whereType<PrecioDeProducto>().singleWhere((p) => p.nombre == nombre);

  group('escenarios de la HU-CAT-006', () {
    test('dado que Rivera no tiene excepción, cuando trabajo en Rivera, veo el precio general '
        'de «Conflicto de los Siglos»: \$U 450', () async {
      await bajar({
        'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
        'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
        'precio_por_ciudad': [_excepcion('ppc-1', _montevideo, 48000, producto: 'pro-1')],
      });

      final enRivera = producto(await precios(_rivera), 'Conflicto de los Siglos');
      expect(enRivera.centavos, 45000);
      expect(enRivera.origen, OrigenDelPrecio.general);
      // La excepción es de Montevideo: allá rige la de la ciudad, no el general.
      final enMontevideo = producto(await precios(_montevideo), 'Conflicto de los Siglos');
      expect(enMontevideo.centavos, 48000);
      expect(enMontevideo.origen, OrigenDelPrecio.ciudad);
    });

    test('dado el combo «Pack Familiar» a \$U 1.200, cuando abro Precios, lo veo como un solo '
        'ítem con su precio y los productos que lo componen', () async {
      await bajar({
        'producto': [
          _producto('pro-1', 'Conflicto de los Siglos'),
          _producto('pro-2', 'El Camino a Cristo'),
        ],
        'coleccion': [_combo('col-1', 'Pack Familiar', aElegir: 1)],
        'producto_coleccion': [
          _componente('pc-1', 'pro-1', 'col-1', cantidad: 2),
          _componente('pc-2', 'pro-2', 'col-1'),
        ],
        'precio_general': [_general('pg-1', 120000, combo: 'col-1')],
      });

      final items = await precios(_rivera);

      final combo = items.whereType<PrecioDeCombo>().single;
      expect([combo.nombre, combo.centavos, combo.librosAElegir], ['Pack Familiar', 120000, 1]);
      expect(combo.componentes, const [
        ComponenteDeCombo(nombre: 'Conflicto de los Siglos', cantidad: 2),
        ComponenteDeCombo(nombre: 'El Camino a Cristo'),
      ]);
      // Un solo ítem para el combo: sus libros no aparecen sueltos sin precio propio.
      expect(items.whereType<PrecioDeProducto>(), isEmpty);
    });

    test('dado que tengo 200 productos, cuando busco «conflicto», se filtran los que contienen '
        'la palabra', () async {
      await bajar({
        'producto': [
          for (var i = 0; i < 198; i++)
            _producto('pro-${i.toString().padLeft(3, '0')}', 'Libro $i'),
          _producto('pro-x1', 'El Conflicto de los Siglos'),
          _producto('pro-x2', 'Conflictos del hogar'),
        ],
        'precio_general': [
          for (var i = 0; i < 198; i++)
            _general('pg-$i', 10000 + i, producto: 'pro-${i.toString().padLeft(3, '0')}'),
          _general('pg-x1', 45000, producto: 'pro-x1'),
          _general('pg-x2', 30000, producto: 'pro-x2'),
        ],
      });

      final items = await precios(_rivera);

      expect(items, hasLength(200));
      final hallados = ResolvedorDePrecios.buscar(items, 'conflicto');
      expect(hallados.map((i) => i.nombre), ['Conflictos del hogar', 'El Conflicto de los Siglos']);
    });

    test(
      'la búsqueda también encuentra por el código del editor, sin importar mayúsculas',
      () async {
        await bajar({
          'producto': [
            _producto('pro-1', 'Conflicto de los Siglos', codigo: 'CS-01'),
            _producto('pro-2', 'El Camino a Cristo'),
          ],
          'precio_general': [
            _general('pg-1', 45000, producto: 'pro-1'),
            _general('pg-2', 30000, producto: 'pro-2'),
          ],
        });

        final items = await precios(_rivera);

        expect(producto(items, 'Conflicto de los Siglos').codigoEditor, 'CS-01');
        expect(producto(items, 'El Camino a Cristo').codigoEditor, isNull);
        expect(ResolvedorDePrecios.buscar(items, 'cs-01').map((i) => i.nombre), [
          'Conflicto de los Siglos',
        ]);
      },
    );
  });

  group('qué se ofrece y a qué precio', () {
    test('sin excepción ni precio general el producto no se ofrece', () async {
      await bajar({
        'producto': [_producto('pro-1', 'Sin precio'), _producto('pro-2', 'Con precio')],
        'precio_general': [_general('pg-2', 30000, producto: 'pro-2')],
        // La excepción es de otra ciudad: para Rivera es como si no existiera.
        'precio_por_ciudad': [_excepcion('ppc-1', _montevideo, 40000, producto: 'pro-1')],
      });

      final items = await precios(_rivera);

      expect(items.map((i) => i.nombre), ['Con precio']);
    });

    test('una excepción vencida o que todavía no empezó no rige: vale el general', () async {
      await bajar({
        'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
        'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
        'precio_por_ciudad': [
          _excepcion('ppc-1', _rivera, 41000, producto: 'pro-1', hasta: '2026-10-27'),
          _excepcion('ppc-2', _rivera, 52000, producto: 'pro-1', desde: '2026-10-29'),
        ],
      });

      final p = producto(await precios(_rivera), 'Conflicto de los Siglos');

      expect([p.centavos, p.origen], [45000, OrigenDelPrecio.general]);
    });

    test('una excepción dada de baja deja de regir y vuelve el general', () async {
      await bajar({
        'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
        'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
        'precio_por_ciudad': [_excepcion('ppc-1', _rivera, 41000, producto: 'pro-1', baja: true)],
      });

      final p = producto(await precios(_rivera), 'Conflicto de los Siglos');

      expect([p.centavos, p.origen], [45000, OrigenDelPrecio.general]);
    });

    test('un precio general dado de baja no se ofrece', () async {
      await bajar({
        'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
        'precio_general': [_general('pg-1', 45000, producto: 'pro-1', baja: true)],
      });

      expect(await precios(_rivera), isEmpty);
    });

    test('un producto dado de baja no se ofrece, pero un combo vivo lo sigue nombrando', () async {
      await bajar({
        'producto': [_producto('pro-1', 'Libro retirado', baja: true)],
        'coleccion': [_combo('col-1', 'Pack')],
        'producto_coleccion': [_componente('pc-1', 'pro-1', 'col-1', cantidad: 3)],
        'precio_general': [
          _general('pg-1', 10000, producto: 'pro-1'),
          _general('pg-2', 90000, combo: 'col-1'),
        ],
      });

      final items = await precios(_rivera);

      final combo = items.single as PrecioDeCombo;
      expect(combo.componentes, const [ComponenteDeCombo(nombre: 'Libro retirado', cantidad: 3)]);
    });

    test(
      'un combo dado de baja no se ofrece y un componente quitado del combo no cuenta',
      () async {
        await bajar({
          'producto': [_producto('pro-1', 'Uno'), _producto('pro-2', 'Dos')],
          'coleccion': [_combo('col-1', 'Vivo'), _combo('col-2', 'Retirado', baja: true)],
          'producto_coleccion': [
            _componente('pc-1', 'pro-1', 'col-1'),
            _componente('pc-2', 'pro-2', 'col-1', baja: true),
          ],
          'precio_general': [
            _general('pg-1', 90000, combo: 'col-1'),
            _general('pg-2', 80000, combo: 'col-2'),
          ],
        });

        final items = await precios(_rivera);

        final combo = items.single as PrecioDeCombo;
        expect(combo.nombre, 'Vivo');
        expect(combo.componentes.map((c) => c.nombre), ['Uno']);
      },
    );

    test('el material de trabajo y un tipo que la app no conoce no se ofrecen', () async {
      await bajar({
        'producto': [
          _producto('pro-1', 'Mochila', tipo: 'MATERIAL'),
          _producto('pro-2', 'Algo nuevo', tipo: 'JUGO'),
          _producto('pro-3', 'Revista', tipo: 'REVISTA'),
          _producto('pro-4', 'Ejemplar misionero', tipo: 'MISIONERO', misionero: true),
        ],
        'precio_general': [
          _general('pg-1', 10000, producto: 'pro-1'),
          _general('pg-2', 10000, producto: 'pro-2'),
          _general('pg-3', 5000, producto: 'pro-3'),
          _general('pg-4', 2000, producto: 'pro-4'),
        ],
      });

      final items = await precios(_rivera);

      expect(items.map((i) => i.nombre), ['Ejemplar misionero', 'Revista']);
    });

    test('las marcas de bonificable y misionero llegan al ítem', () async {
      await bajar({
        'producto': [
          _producto('pro-1', 'Bonificable', bonificable: true),
          _producto('pro-2', 'Misionero', misionero: true),
        ],
        'precio_general': [
          _general('pg-1', 10000, producto: 'pro-1'),
          _general('pg-2', 2000, producto: 'pro-2'),
        ],
      });

      final items = await precios(_rivera);

      expect(producto(items, 'Bonificable').esBonificable, isTrue);
      expect(producto(items, 'Bonificable').esMisionero, isFalse);
      expect(producto(items, 'Misionero').esMisionero, isTrue);
      expect(producto(items, 'Misionero').categoria, CategoriaDePrecios.misioneros);
    });

    test(
      'todavía sin nada bajado el catálogo es vacío y no falla: la pantalla decide qué decir',
      () async {
        final catalogo = await datos.leer(_rivera);

        expect(catalogo, const CatalogoLocal());
      },
    );
  });

  group('el catálogo se actualiza solo cuando baja algo (pull o Realtime)', () {
    test('emite el catálogo guardado y después cada cambio de la ciudad', () async {
      final emisiones = <CatalogoLocal>[];
      final suscripcion = datos.observar(_rivera).listen(emisiones.add);
      addTearDown(suscripcion.cancel);
      Future<void> esperarEmisiones(int n) async {
        for (var i = 0; i < 300 && emisiones.length < n; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      await esperarEmisiones(1);
      expect(emisiones.single, const CatalogoLocal());

      await bajar({
        'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
        'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
      });
      await esperarEmisiones(2);
      expect(ResolvedorDePrecios.resolver(emisiones.last, dia: _hoy).map((i) => i.centavos), [
        45000,
      ]);

      // Un cambio de precio en la ciudad se ve sin tocar nada.
      await bajar({
        'precio_por_ciudad': [_excepcion('ppc-1', _rivera, 41000, producto: 'pro-1')],
      });
      await esperarEmisiones(3);
      expect(ResolvedorDePrecios.resolver(emisiones.last, dia: _hoy).map((i) => i.centavos), [
        41000,
      ]);
    });

    test('un cambio de otra ciudad no mueve la pantalla', () async {
      await bajar({
        'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
        'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
      });
      final emisiones = <CatalogoLocal>[];
      final suscripcion = datos.observar(_rivera).listen(emisiones.add);
      addTearDown(suscripcion.cancel);
      for (var i = 0; i < 300 && emisiones.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await bajar({
        'precio_por_ciudad': [_excepcion('ppc-1', _montevideo, 48000, producto: 'pro-1')],
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(emisiones, hasLength(1));
    });

    test(
      'si la base no se puede leer el Stream falla con el aviso 26·10 y no con un catálogo vacío',
      () async {
        final repo = ConsultaDePreciosRepositoryImpl(_DatosRotos(db), logger: loggerMudo());

        await expectLater(repo.observar(_rivera), emitsError(isA<FailurePreciosNoDisponibles>()));
      },
    );

    test('el repositorio entrega lo mismo que lee la fuente', () async {
      await bajar({
        'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
        'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
      });
      final repo = ConsultaDePreciosRepositoryImpl(datos, logger: loggerMudo());

      final catalogo = await repo.observar(_rivera).first;

      expect(catalogo, await datos.leer(_rivera));
      expect(catalogo.productos.single.nombre, 'Conflicto de los Siglos');
    });
  });

  group('los días del aviso de precios viejos (parametro_global)', () {
    DiasDeAntiguedadDePreciosLocal fuente() =>
        DiasDeAntiguedadDePreciosLocal(datos, logger: loggerMudo());

    test('sin la fila todavía en el teléfono rigen los 15 de siempre', () async {
      expect(await fuente().dias(), AntiguedadDePrecios.diasPorDefecto);
      expect(AntiguedadDePrecios.diasPorDefecto, 15);
    });

    test('con la fila que bajó el pull rige el valor de Administración', () async {
      await bajar({
        'parametro_global': [_parametro(30)],
      });

      expect(await fuente().dias(), 30);
    });

    test('si Administración lo cambia, el valor nuevo rige en la próxima lectura', () async {
      await bajar({
        'parametro_global': [_parametro(30)],
      });
      expect(await fuente().dias(), 30);

      await bajar({
        'parametro_global': [_parametro(7)],
      });

      expect(await fuente().dias(), 7);
    });

    test('un parámetro dado de baja vuelve a los 15', () async {
      await bajar({
        'parametro_global': [_parametro(30, baja: true)],
      });

      expect(await fuente().dias(), 15);
    });

    test('un valor que no sirve (menos de 1) no se usa', () async {
      await bajar({
        'parametro_global': [_parametro(0)],
      });

      expect(await fuente().dias(), 15);
    });

    test('otra clave no se confunde con los días de antigüedad', () async {
      await bajar({
        'parametro_global': [_parametro(99, clave: 'otro_parametro')],
      });

      expect(await fuente().dias(), 15);
    });

    test('si por un dato roto hay dos vivas, gana la última modificada', () async {
      await bajar({
        'parametro_global': [
          _parametro(30, id: 'par-a', actualizado: '2026-10-21T12:00:00+00:00'),
          _parametro(45, id: 'par-b', actualizado: '2026-10-25T12:00:00+00:00'),
        ],
      });

      expect(await fuente().dias(), 45);
    });

    test('si la base no se puede leer rigen los 15: el aviso nunca frena ni falla', () async {
      await db.close();

      expect(await fuente().dias(), 15);
    });
  });
}

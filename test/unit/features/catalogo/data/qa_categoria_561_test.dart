// QA de #561 (categoría de cada producto, camino de los datos): las filas entran por el mismo
// `DriftLocalStore` del motor, como las arma `sync.pull`. Casos: cada categoría del servidor (0149)
// se lee igual, un producto de antes del pull (sin categoría) no se ofrece y aparece cuando llega la
// categoría, una categoría que la app no conoce o en minúscula no frena nada ni se ofrece, y nunca se
// cae al `tipo` heredado.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/catalogo/data/datasources/catalogo_local_data_source.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/item_de_precio.dart';
import 'package:colportores_mobile/features/catalogo/domain/services/resolvedor_de_precios.dart';
import 'package:colportores_mobile/features/catalogo/presentation/formato_precios.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/logger_mudo.dart';

const _hoy = '2026-10-28';
const _ciudad = 'cc-mvd';
const _fecha = '2026-10-20T12:00:00+00:00';

Map<String, Object?> _producto(
  String id,
  String nombre, {
  required String tipo,
  required Object? categoria,
  bool bonificable = false,
  bool misionero = false,
  int version = 1,
}) => {
  'id': id,
  'nombre': nombre,
  'descripcion': null,
  'tipo': tipo,
  'categoria': categoria,
  'es_bonificable': bonificable,
  'es_misionero': misionero,
  'precio_base_compra': null,
  'casa_editora': null,
  'imagen_url': null,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': null,
  'sync_version': version,
  'codigo_editor': null,
};

Map<String, Object?> _general(String id, String producto) => {
  'id': id,
  'producto_id': producto,
  'coleccion_id': null,
  'precio_venta': 100000,
  'valido_desde': '2026-01-01',
  'valido_hasta': null,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': null,
  'sync_version': 1,
};

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

  Future<List<ItemDePrecio>> ofrecidos() async =>
      ResolvedorDePrecios.resolver(await datos.leer(_ciudad), dia: _hoy);

  test('cada categoría del servidor se lee en su valor, con el sí/no aparte', () async {
    await bajar({
      'producto': [
        _producto('b', 'B', tipo: 'LIBRO', categoria: 'BONIFICABLES', bonificable: true),
        _producto('m', 'M', tipo: 'MISIONERO', categoria: 'MISIONEROS'),
        _producto('r', 'R', tipo: 'REVISTA', categoria: 'REVISTAS'),
        _producto('e', 'E', tipo: 'LIBRO', categoria: 'ESPIRITUALES', bonificable: true),
        _producto('x', 'X', tipo: 'MATERIAL', categoria: 'MATERIAL'),
      ],
    });
    final por = {for (final p in (await datos.leer(_ciudad)).productos) p.id: p};
    expect(por['b']!.categoria, CategoriaDeProducto.bonificables);
    expect(por['m']!.categoria, CategoriaDeProducto.misioneros);
    expect(por['r']!.categoria, CategoriaDeProducto.revistas);
    expect(por['e']!.categoria, CategoriaDeProducto.espirituales);
    expect(por['e']!.esBonificable, isTrue, reason: 'el sí/no no se pierde');
    expect(por['x']!.categoria, CategoriaDeProducto.material);
  });

  test(
    'un producto de antes del pull (categoría nula) no se ofrece, aunque su tipo sea LIBRO',
    () async {
      await bajar({
        'producto': [_producto('v', 'Libro viejo', tipo: 'LIBRO', categoria: null)],
        'precio_general': [_general('g', 'v')],
      });
      expect((await datos.leer(_ciudad)).productos.single.categoria, CategoriaDeProducto.otra);
      expect(await ofrecidos(), isEmpty);
    },
  );

  test('cuando el próximo pull trae la categoría, el producto aparece con su etiqueta', () async {
    await bajar({
      'producto': [_producto('v', 'Libro viejo', tipo: 'LIBRO', categoria: null)],
      'precio_general': [_general('g', 'v')],
    });
    expect(await ofrecidos(), isEmpty);
    await bajar({
      'producto': [
        _producto('v', 'Libro viejo', tipo: 'LIBRO', categoria: 'ESPIRITUALES', version: 2),
      ],
    });
    final items = await ofrecidos();
    expect(items, hasLength(1));
    final p = items.single as PrecioDeProducto;
    expect(FormatoPrecios.etiquetasDe(p), [EtiquetaDeProducto.espiritual]);
  });

  test('una categoría que la app no conoce no frena el pull ni se ofrece', () async {
    await bajar({
      'producto': [
        _producto('n', 'Categoría nueva', tipo: 'LIBRO', categoria: 'DIGITALES'),
        _producto('ok', 'Libro bueno', tipo: 'LIBRO', categoria: 'ESPIRITUALES'),
      ],
      'precio_general': [_general('g1', 'n'), _general('g2', 'ok')],
    });
    expect((await ofrecidos()).map((i) => i.nombre), ['Libro bueno']);
  });

  test(
    'la categoría en minúscula o con espacios no es una categoría (el servidor manda MAYÚSCULAS)',
    () async {
      await bajar({
        'producto': [
          _producto('a', 'Minúscula', tipo: 'LIBRO', categoria: 'espirituales'),
          _producto('b', 'Con espacio', tipo: 'LIBRO', categoria: ' ESPIRITUALES'),
          _producto('c', 'Vacía', tipo: 'LIBRO', categoria: ''),
        ],
        'precio_general': [_general('g1', 'a'), _general('g2', 'b'), _general('g3', 'c')],
      });
      expect(await ofrecidos(), isEmpty);
    },
  );

  test('la categoría manda sobre el tipo heredado y sobre es_misionero', () async {
    await bajar({
      'producto': [
        _producto('m', 'Tipo LIBRO, categoría MATERIAL', tipo: 'LIBRO', categoria: 'MATERIAL'),
        _producto(
          'e',
          'Tipo MISIONERO, categoría ESPIRITUALES',
          tipo: 'MISIONERO',
          categoria: 'ESPIRITUALES',
          misionero: true,
        ),
      ],
      'precio_general': [_general('g1', 'm'), _general('g2', 'e')],
    });
    final items = await ofrecidos();
    expect(items.map((i) => i.nombre), ['Tipo MISIONERO, categoría ESPIRITUALES']);
    final p = items.single as PrecioDeProducto;
    expect(p.categoria, CategoriaDePrecios.libros);
    expect(FormatoPrecios.etiquetasDe(p), [EtiquetaDeProducto.espiritual]);
  });

  test(
    'a una categoría que cambia en el servidor la sigue la etiqueta (corrección de Administración)',
    () async {
      await bajar({
        'producto': [_producto('p', 'Libro', tipo: 'LIBRO', categoria: 'ESPIRITUALES')],
        'precio_general': [_general('g', 'p')],
      });
      expect(FormatoPrecios.etiquetasDe((await ofrecidos()).single as PrecioDeProducto), [
        EtiquetaDeProducto.espiritual,
      ]);
      await bajar({
        'producto': [
          _producto('p', 'Libro', tipo: 'MISIONERO', categoria: 'MISIONEROS', version: 2),
        ],
      });
      final p = (await ofrecidos()).single as PrecioDeProducto;
      expect(p.categoria, CategoriaDePrecios.misioneros);
      expect(FormatoPrecios.etiquetasDe(p), [EtiquetaDeProducto.misionero]);
    },
  );
}

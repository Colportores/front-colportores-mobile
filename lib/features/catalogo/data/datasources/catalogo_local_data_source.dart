import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/catalogo_local.dart';

/// Lectura del catálogo de ventas desde la DB local (HU-CAT-006, HU-CAT-007). Solo lee: `producto`,
/// `coleccion`, `producto_coleccion`, `precio_por_ciudad`, `precio_general` y `parametro_global` son
/// réplicas del servidor y la app nunca las escribe (contrato-sync-engine §2, política `pull`).
///
/// Arma valores del dominio ([CatalogoLocal]) y no filas de Drift: lo que decide cuánto sale algo en
/// una ciudad es el `ResolvedorDePrecios`, que no sabe de dónde vienen los datos.
class CatalogoLocalDataSource {
  CatalogoLocalDataSource(this._db);

  final AppDatabase _db;

  /// La clave de `parametro_global` con los días del aviso fuerte de precios viejos.
  static const claveDiasDeAntiguedad = 'dias_antiguedad_precios';

  /// El catálogo para la ciudad de la campaña [campaniaCiudadId] ([leer]), ahora y cada vez que el
  /// pull o el Realtime cambian algo de las cinco tablas que lo forman. No repite una emisión igual
  /// a la anterior (el cambio de una excepción de **otra** ciudad no mueve la pantalla).
  Stream<CatalogoLocal> observar(String campaniaCiudadId) {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.productos,
            _db.colecciones,
            _db.productoColecciones,
            _db.preciosPorCiudad,
            _db.preciosGenerales,
          },
        )
        .watch()
        .asyncMap((_) => leer(campaniaCiudadId))
        .distinct();
  }

  /// El catálogo de la ciudad [campaniaCiudadId], leído de una vez: **todos** los productos y combos
  /// (los dados de baja, marcados, porque un combo vivo sigue nombrando a un libro que ya no se
  /// ofrece suelto), las excepciones de **esa** ciudad y los precios generales, estos dos sin las
  /// bajas lógicas. Los componentes quitados de un combo (`deleted_at`) no cuentan.
  ///
  /// En una transacción: un pull que aplica a mitad de la lectura no deja un precio sin su producto.
  Future<CatalogoLocal> leer(String campaniaCiudadId) {
    return _db.transaction(() async {
      final productos = await (_db.select(
        _db.productos,
      )..orderBy([(p) => OrderingTerm.asc(p.id)])).get();
      final combos = await (_db.select(
        _db.colecciones,
      )..orderBy([(c) => OrderingTerm.asc(c.id)])).get();
      final componentes =
          await (_db.select(_db.productoColecciones)
                ..where((c) => c.deletedAt.isNull())
                ..orderBy([(c) => OrderingTerm.asc(c.id)]))
              .get();
      final excepciones =
          await (_db.select(_db.preciosPorCiudad)
                ..where((p) => p.campaniaCiudadId.equals(campaniaCiudadId) & p.deletedAt.isNull())
                ..orderBy([(p) => OrderingTerm.asc(p.id)]))
              .get();
      final generales =
          await (_db.select(_db.preciosGenerales)
                ..where((p) => p.deletedAt.isNull())
                ..orderBy([(p) => OrderingTerm.asc(p.id)]))
              .get();

      final componentesPorCombo = <String, List<ComponenteDelCombo>>{};
      for (final c in componentes) {
        componentesPorCombo
            .putIfAbsent(c.coleccionId, () => [])
            .add(ComponenteDelCombo(productoId: c.productoId, cantidad: c.cantidad));
      }

      return CatalogoLocal(
        productos: [
          for (final p in productos)
            ProductoDelCatalogo(
              id: p.id,
              nombre: p.nombre,
              tipo: TipoDeProducto.desdeCodigo(p.tipo),
              esBonificable: p.esBonificable,
              esMisionero: p.esMisionero,
              codigoEditor: p.codigoEditor,
              dadoDeBaja: p.deletedAt != null,
            ),
        ],
        combos: [
          for (final c in combos)
            ComboDelCatalogo(
              id: c.id,
              nombre: c.nombre,
              librosAElegir: c.librosAElegir,
              componentes: componentesPorCombo[c.id] ?? const [],
              dadoDeBaja: c.deletedAt != null,
            ),
        ],
        excepciones: [
          for (final p in excepciones)
            PrecioDelCatalogo(
              id: p.id,
              productoId: p.productoId,
              comboId: p.coleccionId,
              centavos: p.precioVenta,
              validoDesde: p.validoDesde,
              validoHasta: p.validoHasta,
            ),
        ],
        generales: [
          for (final p in generales)
            PrecioDelCatalogo(
              id: p.id,
              productoId: p.productoId,
              comboId: p.coleccionId,
              centavos: p.precioVenta,
              validoDesde: p.validoDesde,
              validoHasta: p.validoHasta,
            ),
        ],
      );
    });
  }

  /// El valor vivo de `parametro_global.dias_antiguedad_precios`, o `null` si la fila todavía no bajó
  /// o está dada de baja. Si por un dato roto hubiera más de una viva, gana la última modificada.
  Future<int?> diasDeAntiguedadDeLosPrecios() async {
    final fila =
        await (_db.select(_db.parametrosGlobales)
              ..where((p) => p.clave.equals(claveDiasDeAntiguedad) & p.deletedAt.isNull())
              ..orderBy([(p) => OrderingTerm.desc(p.updatedAt), (p) => OrderingTerm.desc(p.id)])
              ..limit(1))
            .getSingleOrNull();
    return fila?.valor;
  }
}

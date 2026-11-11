import 'package:equatable/equatable.dart';

/// Lo que dice el catálogo de ventas replicado en el teléfono (`producto`, `coleccion`,
/// `producto_coleccion`, `precio_por_ciudad`, `precio_general`; HU-CAT-007), tal cual y sin resolver
/// precios: de ahí sale la consulta de precios (HU-CAT-006, vista 26).
///
/// Son valores del dominio y no filas de Drift: la lectura de la réplica los arma y el
/// `ResolvedorDePrecios` los combina sin saber de dónde vienen.

/// La categoría de un producto del catálogo (`producto.categoria`, backend-supabase 0149): una por
/// producto, en lugar del `tipo` de antes (decisión de Cristian, 28/10, «Categorías»). Es la etiqueta
/// que ve la colportora en Precios; que el producto cuente para la beca lo dice aparte
/// [ProductoDelCatalogo.esBonificable] (sí/no).
enum CategoriaDeProducto {
  bonificables('BONIFICABLES'),
  misioneros('MISIONEROS'),
  revistas('REVISTAS'),

  /// El libro común, ni bonificable ni misionero (la etiqueta «✝ Espiritual»).
  espirituales('ESPIRITUALES'),

  /// Material de trabajo, de uso interno: no se vende, así que no aparece en los precios.
  material('MATERIAL'),

  /// Una categoría que esta versión de la app todavía no conoce (el servidor sumó una) o un producto
  /// cuya categoría aún no bajó del servidor: no frena nada, pero tampoco se ofrece, porque no se
  /// sabe qué es. No se deriva de `tipo`: la categoría es la fuente (decisión de Cristian, 28/10).
  otra('');

  const CategoriaDeProducto(this.codigo);

  final String codigo;

  /// Lo que se ofrece y tiene precio: todo menos el material y lo que no se conoce.
  bool get seVende => this != material && this != otra;

  static CategoriaDeProducto desdeCodigo(String? codigo) =>
      values.firstWhere((c) => c.codigo.isNotEmpty && c.codigo == codigo, orElse: () => otra);
}

/// Un producto del catálogo (`producto`).
final class ProductoDelCatalogo extends Equatable {
  const ProductoDelCatalogo({
    required this.id,
    required this.nombre,
    required this.categoria,
    this.esBonificable = false,
    this.esMisionero = false,
    this.codigoEditor,
    this.dadoDeBaja = false,
  });

  final String id;
  final String nombre;
  final CategoriaDeProducto categoria;

  /// Cuenta para la beca del colportor (el ícono ◆ de la vista 26).
  final bool esBonificable;

  /// Ejemplar misionero (el ícono ✦ de la vista 26).
  final bool esMisionero;

  /// El código que le asignó la casa editora (`producto.codigo_editor`): opcional y no único. Sin
  /// código el producto se encuentra por nombre.
  final String? codigoEditor;

  /// Baja lógica (`deleted_at`): un producto dado de baja deja de ofrecerse.
  final bool dadoDeBaja;

  @override
  List<Object?> get props => [
    id,
    nombre,
    categoria,
    esBonificable,
    esMisionero,
    codigoEditor,
    dadoDeBaja,
  ];
}

/// Cuántas unidades de un producto lleva un combo (`producto_coleccion`).
final class ComponenteDelCombo extends Equatable {
  const ComponenteDelCombo({required this.productoId, this.cantidad = 1});

  final String productoId;
  final int cantidad;

  @override
  List<Object?> get props => [productoId, cantidad];
}

/// Un combo (`coleccion`): una colección con precio propio (HU-CAT-009).
final class ComboDelCatalogo extends Equatable {
  const ComboDelCatalogo({
    required this.id,
    required this.nombre,
    this.librosAElegir = 0,
    this.componentes = const [],
    this.dadoDeBaja = false,
  });

  final String id;
  final String nombre;

  /// Cuántos libros del catálogo elige quien vende, además de lo fijo del combo. `0` = combo fijo.
  final int librosAElegir;

  /// Lo que lleva siempre.
  final List<ComponenteDelCombo> componentes;

  final bool dadoDeBaja;

  @override
  List<Object?> get props => [id, nombre, librosAElegir, componentes, dadoDeBaja];
}

/// Un precio de venta vigente o no, de un producto **o** de un combo: viene de `precio_por_ciudad`
/// (la excepción de una ciudad de la campaña) o de `precio_general` (el de todo el país).
final class PrecioDelCatalogo extends Equatable {
  const PrecioDelCatalogo({
    required this.id,
    required this.centavos,
    required this.validoDesde,
    this.productoId,
    this.comboId,
    this.validoHasta,
  }) : assert(
         (productoId == null) != (comboId == null),
         'Un precio es de un producto o de un combo, nunca de los dos ni de ninguno',
       );

  final String id;

  /// El producto, o `null` si el precio es de un combo.
  final String? productoId;

  /// El combo, o `null` si el precio es de un producto.
  final String? comboId;

  /// En centavos (nunca `double`: flutter-clean-arch.md, regla 6).
  final int centavos;

  /// Primer día en que vale (inclusive), `AAAA-MM-DD`: un día de Montevideo, no un instante.
  final String validoDesde;

  /// Último día en que vale (inclusive), `AAAA-MM-DD`; `null` = vigente hasta nuevo aviso.
  final String? validoHasta;

  /// Vale el día [dia] (`AAAA-MM-DD`)? Las fechas ISO comparan bien como texto.
  bool valeEl(String dia) =>
      validoDesde.compareTo(dia) <= 0 && (validoHasta == null || validoHasta!.compareTo(dia) >= 0);

  @override
  List<Object?> get props => [id, productoId, comboId, centavos, validoDesde, validoHasta];
}

/// El catálogo replicado en el teléfono para **una ciudad de una campaña**: todos los productos y
/// combos, las excepciones de esa ciudad y los precios generales.
final class CatalogoLocal extends Equatable {
  const CatalogoLocal({
    this.productos = const [],
    this.combos = const [],
    this.excepciones = const [],
    this.generales = const [],
  });

  final List<ProductoDelCatalogo> productos;
  final List<ComboDelCatalogo> combos;

  /// Las filas de `precio_por_ciudad` de **esa** ciudad (sin bajas), vigentes o no.
  final List<PrecioDelCatalogo> excepciones;

  /// Las filas de `precio_general` (sin bajas), vigentes o no.
  final List<PrecioDelCatalogo> generales;

  @override
  List<Object?> get props => [productos, combos, excepciones, generales];
}

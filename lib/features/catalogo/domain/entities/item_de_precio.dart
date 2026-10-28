import 'package:equatable/equatable.dart';

import 'catalogo_local.dart';

/// De dónde sale el precio que ve la colportora: la excepción de su ciudad o el precio general de
/// todo el país (decisión de Cristian, 06/10, «Precio gral.»; R-CT05).
enum OrigenDelPrecio { ciudad, general }

/// Las pestañas de filtro de la vista 26.
enum CategoriaDePrecios { colecciones, libros, misioneros, revistas }

/// Un ítem de la consulta de precios con el precio ya resuelto para una ciudad y un día.
sealed class ItemDePrecio extends Equatable {
  const ItemDePrecio({
    required this.id,
    required this.nombre,
    required this.centavos,
    required this.origen,
  });

  final String id;
  final String nombre;

  /// El precio vigente, en centavos.
  final int centavos;

  final OrigenDelPrecio origen;
}

/// Un producto (libro, revista o ejemplar misionero) con su precio.
final class PrecioDeProducto extends ItemDePrecio {
  const PrecioDeProducto({
    required super.id,
    required super.nombre,
    required super.centavos,
    required super.origen,
    required this.tipo,
    this.esBonificable = false,
    this.esMisionero = false,
    this.codigoEditor,
  });

  final TipoDeProducto tipo;
  final bool esBonificable;
  final bool esMisionero;
  final String? codigoEditor;

  /// En qué pestaña de la vista 26 está: el ejemplar misionero va en «Misioneros» aunque su
  /// `tipo` sea `LIBRO`.
  CategoriaDePrecios get categoria {
    if (esMisionero || tipo == TipoDeProducto.misionero) return CategoriaDePrecios.misioneros;
    if (tipo == TipoDeProducto.revista) return CategoriaDePrecios.revistas;
    return CategoriaDePrecios.libros;
  }

  @override
  List<Object?> get props => [
    id,
    nombre,
    centavos,
    origen,
    tipo,
    esBonificable,
    esMisionero,
    codigoEditor,
  ];
}

/// Un producto que lleva un combo, con cuántas unidades.
final class ComponenteDeCombo extends Equatable {
  const ComponenteDeCombo({required this.nombre, this.cantidad = 1});

  final String nombre;
  final int cantidad;

  @override
  List<Object?> get props => [nombre, cantidad];
}

/// Un combo: un solo ítem con su precio y los productos que lo componen (R-CT06).
final class PrecioDeCombo extends ItemDePrecio {
  const PrecioDeCombo({
    required super.id,
    required super.nombre,
    required super.centavos,
    required super.origen,
    this.librosAElegir = 0,
    this.componentes = const [],
  });

  /// Cuántos libros del catálogo elige quien vende además de lo fijo. `0` = combo fijo.
  final int librosAElegir;

  /// Lo que lleva siempre, en el orden del combo.
  final List<ComponenteDeCombo> componentes;

  @override
  List<Object?> get props => [id, nombre, centavos, origen, librosAElegir, componentes];
}

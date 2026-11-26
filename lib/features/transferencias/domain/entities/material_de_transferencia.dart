import 'package:equatable/equatable.dart';

import '../../../catalogo/domain/entities/item_de_precio.dart' show CategoriaDePrecios;

/// Un material que se puede pedir (vista 40, 40A·01): un producto del catálogo, sin precio (la
/// transferencia mueve materiales, no plata), con lo que el colportor tiene hoy («Tenés 3»).
final class MaterialDeTransferencia extends Equatable {
  const MaterialDeTransferencia({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.tengo,
    this.esBonificable = false,
  });

  final String id;
  final String nombre;

  /// En qué chip está: libros, misioneros o revistas (las mismas pestañas que Precios, sin colecciones).
  final CategoriaDePrecios categoria;

  /// Lo que dice el stock del colportor (`stock.cantidad_disponible`); 0 si el servidor no le registra.
  /// Puede ser negativo (S46): se muestra tal cual.
  final int tengo;

  /// Cuenta para la beca: la etiqueta «◆ Bonificable».
  final bool esBonificable;

  @override
  List<Object?> get props => [id, nombre, categoria, tengo, esBonificable];
}

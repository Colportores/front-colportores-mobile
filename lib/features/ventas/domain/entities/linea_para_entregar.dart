import 'package:equatable/equatable.dart';

import 'componente_vendido.dart';

/// Una fila de «Qué entregás» (27B·01): lo que la colportora puede tildar o destildar. Puede ser un
/// producto suelto, un libro de una colección o la base de una colección (lo que va siempre).
final class LineaParaEntregar extends Equatable {
  const LineaParaEntregar({
    required this.clave,
    required this.nombre,
    required this.titulo,
    required this.productos,
    this.detalle,
  });

  /// Identifica la fila en pantalla (no es un id guardado).
  final String clave;

  /// «Salud y Hogar»: cómo se llama lo que cuenta la fila, sin la cantidad.
  final String nombre;

  /// «Salud y Hogar × 1».
  final String titulo;

  /// «Base de la colección» en la fila de lo que siempre va; `null` en el resto.
  final String? detalle;

  /// Los productos y cuántas unidades de cada uno cuenta la fila (la base junta varios).
  final List<ComponenteVendido> productos;

  @override
  List<Object?> get props => [clave, nombre, titulo, detalle, productos];
}

import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Un misionero que la colportora dejó en una entrevista sin venta (`visita_misionero`,
/// backend-supabase 0160): el producto y cuántos. No es una venta: no lleva talonario ni monto
/// (decisiones de Cristian, 03/11, «Talonario mis», y 04/11, «Misio. entrev»). El servidor descuenta
/// el stock de la colportora con un movimiento propio.
///
/// Cuelga de la visita por un id opaco y no lleva ningún dato del cliente. `colportor_id` lo fija el
/// servidor desde el JWT: el teléfono no lo manda.
final class MisioneroDejado extends Equatable {
  const MisioneroDejado({
    required this.id,
    required this.visitaId,
    required this.productoId,
    required this.cantidad,
    required this.auditoria,
  });

  final String id;
  final String visitaId;

  /// Un producto de categoría MISIONEROS (el servidor rechaza otro con 23514).
  final String productoId;

  /// 1 o más.
  final int cantidad;

  final Auditoria auditoria;

  @override
  List<Object?> get props => [id, visitaId, productoId, cantidad, auditoria];
}

/// Un misionero que se puede anotar en «Lo que dejaste»: lo que muestra el paso, sin precio.
final class MisioneroParaDejar extends Equatable {
  const MisioneroParaDejar({required this.productoId, required this.nombre});

  final String productoId;
  final String nombre;

  @override
  List<Object?> get props => [productoId, nombre];
}

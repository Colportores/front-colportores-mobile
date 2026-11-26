import 'package:equatable/equatable.dart';

import '../../../catalogo/domain/entities/catalogo_local.dart';

/// Las categorías que se ofrecen al armar el pedido: las tres del canvas (37A·01), «Libros», «Misioneros» y
/// «Revistas», y la cuarta, «Materiales» (decisión de Cristian, 24/11, «Pedir mater.», #769): el material
/// de trabajo se pide como otra categoría, con el costo de la casa editora.
enum CategoriaDelPedido {
  libros('Libros'),
  misioneros('Misioneros'),
  revistas('Revistas'),
  materiales('Materiales');

  const CategoriaDelPedido(this.rotulo);

  final String rotulo;

  /// La categoría del pedido de una categoría del catálogo, o `null` si no se pide (lo que no se conoce).
  static CategoriaDelPedido? de(CategoriaDeProducto categoria) => switch (categoria) {
    CategoriaDeProducto.bonificables || CategoriaDeProducto.espirituales => libros,
    CategoriaDeProducto.misioneros => misioneros,
    CategoriaDeProducto.revistas => revistas,
    CategoriaDeProducto.material => materiales,
    CategoriaDeProducto.otra => null,
  };
}

/// Un producto que se puede pedir a la casa editora, con lo que cuesta y lo que ya tiene la colportora.
final class ProductoPedible extends Equatable {
  const ProductoPedible({
    required this.id,
    required this.nombre,
    required this.categoriaDelCatalogo,
    required this.precioDeCompraCentavos,
    this.stock = 0,
    this.esBonificable = false,
  });

  final String id;
  final String nombre;
  final CategoriaDeProducto categoriaDelCatalogo;

  /// El costo de la casa editora (`producto.precio_base_compra`), no el precio de venta.
  final int precioDeCompraCentavos;

  /// Lo que la colportora tiene hoy; sin fila de stock, 0. Puede ser negativo (S46).
  final int stock;

  final bool esBonificable;

  CategoriaDelPedido? get categoria => CategoriaDelPedido.de(categoriaDelCatalogo);

  @override
  List<Object?> get props => [
    id,
    nombre,
    categoriaDelCatalogo,
    precioDeCompraCentavos,
    stock,
    esBonificable,
  ];
}

/// Lo que sabe el teléfono de la situación de la colportora antes de enviar (HU-STK-009): sale de lo que
/// bajó con la sincronización y de lo que hay en el teléfono. Sin conexión es lo último que se sincronizó.
final class SituacionDelColportor extends Equatable {
  const SituacionDelColportor({
    required this.deudaActualCentavos,
    required this.porCobrarCentavos,
    required this.librosPorEntregar,
    this.limiteDeudaCentavos,
    this.deudaLeidaEn,
  });

  /// La deuda con la casa editora hoy (la cuenta del servidor; sin cuenta, 0).
  final int deudaActualCentavos;

  /// Lo que le deben los clientes (la cifra «Por cobrar» de Mi Cuenta).
  final int porCobrarCentavos;

  /// Las unidades vendidas que todavía no entregó.
  final int librosPorEntregar;

  /// El límite de deuda de su campaña (`campania.limite_deuda`); `null` = la campaña no tiene límite o no
  /// se sabe cuál es: no hay aviso.
  final int? limiteDeudaCentavos;

  /// Cuándo bajó por última vez lo que cuenta la deuda; `null` = nunca bajó nada.
  final DateTime? deudaLeidaEn;

  @override
  List<Object?> get props => [
    deudaActualCentavos,
    porCobrarCentavos,
    librosPorEntregar,
    limiteDeudaCentavos,
    deudaLeidaEn,
  ];
}

/// Lo de la situación que sale solo de la base del teléfono: lo que falta entregar y el límite de la campaña.
/// La deuda y el «Por cobrar» salen de Mi Cuenta (HU-CTA-002, HU-CTA-003) y se suman en
/// [SituacionDelColportor].
final class ContextoLocalDelPedido extends Equatable {
  const ContextoLocalDelPedido({required this.librosPorEntregar, this.limiteDeudaCentavos});

  /// Las unidades de las entregas pendientes de sus ventas (HU-VEN-003).
  final int librosPorEntregar;

  /// `campania.limite_deuda` de la campaña de la colportora; `null` = sin límite o campaña desconocida.
  final int? limiteDeudaCentavos;

  @override
  List<Object?> get props => [librosPorEntregar, limiteDeudaCentavos];
}

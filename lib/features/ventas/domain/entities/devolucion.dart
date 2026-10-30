import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../mapa/domain/entities/color_house_status.dart';

/// Un libro que vuelve al colportor, con el renglón de la venta del que salió (el suelto o el combo):
/// un elemento de `devolucion.productos_devueltos` (esquema-datos.md, migración 0136, decisión de
/// Cristian del 27/10, «Devol. combo»).
///
/// Un combo se devuelve con un elemento por libro, todos con el renglón del combo. Sin precios: salen
/// del renglón de la venta.
final class ProductoDevuelto extends Equatable {
  const ProductoDevuelto({
    required this.productoId,
    required this.ventaItemId,
    required this.cantidad,
  });

  /// FK a `producto.id`.
  final String productoId;

  /// FK a `venta_item.id`: el renglón de la venta del que sale el libro.
  final String ventaItemId;

  /// Cuántas unidades de [productoId] vuelven; siempre 1 o más.
  final int cantidad;

  @override
  List<Object?> get props => [productoId, ventaItemId, cantidad];
}

/// Qué hace la colportora con la plata que el cliente pagó de más (vista 31, 31-02): las tres salidas
/// de HU-VEN-004. La pantalla propone «Lo retengo», la que no devuelve plata (decisión de Cristian, 23/10,
/// «Debo cliente»); el use case recibe siempre la salida elegida.
enum QueHacerConLaDiferencia {
  /// «Se lo devuelvo ahora»: la devolución guarda lo devuelto en `monto_reembolsado` y «En mano» lo
  /// resta (decisión de Cristian, 23/10, «Reembolso»).
  devolverAhora,

  /// «Lo retengo»: la diferencia queda como `dinero_retenido`, como compensación; el saldo queda en
  /// cero.
  retener,

  /// «Se lo devuelvo después»: no guarda monto; el saldo negativo es «Debo al cliente».
  devolverDespues,
}

/// Una devolución de una venta (`devolucion`, ADR-002, HU-VEN-004): qué libros vuelven y qué se hace
/// con el dinero. La venta original no se toca ni se anula.
///
/// Todo el dinero va en centavos (`int`). Es una fila del push: sube sin dato del cliente
/// (`venta_id` y los ids de producto y de renglón son opacos). El [motivo] es texto libre que lee la
/// coordinadora (decisión de Cristian, 27/10, «Motivo devol.»): la pantalla avisa que no se pongan
/// datos del cliente.
class Devolucion extends Equatable {
  Devolucion({
    required this.id,
    required this.ventaId,
    required List<ProductoDevuelto> productos,
    this.dineroRetenidoCentavos = 0,
    this.montoReembolsadoCentavos,
    this.motivo,
    required DateTime fechaDevolucion,
    required this.auditoria,
  }) : productos = List.unmodifiable(productos),
       fechaDevolucion = instanteMs(fechaDevolucion);

  final String id;

  /// FK a `venta.id`.
  final String ventaId;

  /// Lo que vuelve: al menos un elemento.
  final List<ProductoDevuelto> productos;

  /// Lo que la colportora se queda cuando el cliente pagó de más y elige «Lo retengo»; 0 si no
  /// retiene nada.
  final int dineroRetenidoCentavos;

  /// Lo que se le devolvió al cliente en el momento («Se lo devuelvo ahora»); `null` si no devolvió
  /// plata.
  final int? montoReembolsadoCentavos;

  /// Por qué se devuelve, de 1 a 500 caracteres y sin espacios en los bordes; `null` si no lo dijo.
  final String? motivo;

  /// Cuándo se registró (UTC), según el teléfono.
  final DateTime fechaDevolucion;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [
    id,
    ventaId,
    productos,
    dineroRetenidoCentavos,
    montoReembolsadoCentavos,
    motivo,
    fechaDevolucion,
    auditoria,
  ];
}

/// Lo que pide la colportora al registrar una devolución: qué vuelve y qué hace con la plata de más.
/// Los libros, los montos y el estado de la venta los calcula y comprueba quien guarda, dentro de la
/// transacción, con lo que hay en el teléfono en ese momento.
final class PedidoDeDevolucion extends Equatable {
  const PedidoDeDevolucion({
    required this.id,
    required this.ventaId,
    required this.colportorId,
    required this.unidadesPorRenglon,
    this.queHacer,
    this.motivo,
    required this.ahora,
  });

  /// El id de la devolución; se repite en los reintentos con los mismos datos.
  final String id;

  final String ventaId;

  /// Quién registra: el `created_by` de la fila.
  final String colportorId;

  /// Cuántas unidades de cada renglón vuelven: `venta_item.id` → unidades.
  final Map<String, int> unidadesPorRenglon;

  /// Qué hace con la plata de más. Obligatoria si el cliente pagó de más; si no, se ignora.
  final QueHacerConLaDiferencia? queHacer;

  /// El motivo, ya limpio (ver `ReglasDeDevolucion.motivo`); `null` si no lo dijo.
  final String? motivo;

  /// El instante del registro (UTC): su `fecha_devolucion` y la hora contra la que corren las 72 h.
  final DateTime ahora;

  @override
  List<Object?> get props => [
    id,
    ventaId,
    colportorId,
    unidadesPorRenglon,
    queHacer,
    motivo,
    ahora,
  ];
}

/// La devolución ya guardada, con cómo quedó la venta y la casa. Todo en centavos.
final class DevolucionRegistrada extends Equatable {
  const DevolucionRegistrada({
    required this.devolucion,
    required this.totalCentavos,
    required this.saldoCentavos,
    required this.deboAlClienteCentavos,
    required this.eraTotal,
    this.colorDeLaCasa,
    this.yaEstaba = false,
  });

  final Devolucion devolucion;

  /// Lo que el cliente se queda comprando después de todas las devoluciones («Total de la venta» de
  /// 31-05).
  final int totalCentavos;

  /// Lo que todavía debe el cliente de lo que se queda: nunca negativo.
  final int saldoCentavos;

  /// Lo que la colportora le debe al cliente (compromiso de reembolso): nunca negativo.
  final int deboAlClienteCentavos;

  /// Con esta devolución la venta quedó devuelta por completo.
  final bool eraTotal;

  /// El color de la casa después de devolver (`house_status`); `null` si quedó sin color o la casa no
  /// está en el teléfono.
  final ColorHouseStatus? colorDeLaCasa;

  /// Ya estaba guardada (un doble toque o un reintento con el mismo id): no se escribió nada de
  /// nuevo.
  final bool yaEstaba;

  @override
  List<Object?> get props => [
    devolucion,
    totalCentavos,
    saldoCentavos,
    deboAlClienteCentavos,
    eraTotal,
    colorDeLaCasa,
    yaEstaba,
  ];
}

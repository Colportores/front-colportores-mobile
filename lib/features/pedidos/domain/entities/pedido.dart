import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// En qué punto está un pedido a la casa editora (`pedido_casa_editora.estado`, HU-STK-003 y HU-STK-009).
enum EstadoDelPedido {
  /// Armado en el teléfono; todavía no lo decidió el coordinador (`PENDIENTE_AUTORIZACION`).
  porAutorizar('PENDIENTE_AUTORIZACION'),
  autorizado('AUTORIZADO'),
  despachado('DESPACHADO'),
  recibido('RECIBIDO'),

  /// El coordinador no lo autorizó (`RECHAZADO`, con su motivo): en pantalla es «No autorizado».
  rechazado('RECHAZADO'),

  /// Lo canceló la colportora antes de que lo autorizaran. No se borra (HU-STK-009).
  cancelado('CANCELADO');

  const EstadoDelPedido(this.codigo);

  /// Lo que viaja al servidor y baja de él.
  final String codigo;

  /// Un código que esta versión no conoce se deja como «por autorizar»: el pedido no desaparece y, como
  /// mucho, la colportora ve que todavía no se decidió.
  static EstadoDelPedido desdeCodigo(String codigo) =>
      values.firstWhere((e) => e.codigo == codigo, orElse: () => porAutorizar);

  /// Mientras está por autorizar la colportora lo puede cancelar; después lo decide el coordinador.
  bool get sePuedeCancelar => this == porAutorizar;

  /// «En camino»: el coordinador ya dijo que sí y todavía no llegó.
  bool get enCamino => this == autorizado || this == despachado;
}

/// Una línea de un pedido: qué producto y cuántas unidades.
final class LineaDelPedido extends Equatable {
  const LineaDelPedido({
    required this.id,
    required this.productoId,
    required this.cantidad,
    this.cantidadAutorizada,
    this.precioUnitarioCentavos,
  });

  final String id;
  final String productoId;

  /// Lo que pidió la colportora.
  final int cantidad;

  /// Lo que autorizó el coordinador si redujo la línea; `null` = se autorizó lo pedido.
  final int? cantidadAutorizada;

  /// El costo de la casa editora que fijó el servidor al llegar el pedido; `null` mientras no llegó.
  final int? precioUnitarioCentavos;

  /// Lo que vale la línea para quien la mira: lo autorizado si el coordinador la redujo.
  int get cantidadVigente => cantidadAutorizada ?? cantidad;

  @override
  List<Object?> get props => [id, productoId, cantidad, cantidadAutorizada, precioUnitarioCentavos];
}

/// Un pedido a la casa editora de la colportora (HU-STK-009).
final class Pedido extends Equatable {
  Pedido({
    required this.id,
    required this.colportorId,
    required this.estado,
    required List<LineaDelPedido> lineas,
    required this.fecha,
    required this.montoCentavos,
    required this.auditoria,
    this.excedeLimite = false,
    this.montoAutorizadoCentavos,
    this.motivoRechazo,
    this.numero,
  }) : lineas = List.unmodifiable(lineas);

  final String id;
  final String colportorId;
  final EstadoDelPedido estado;
  final List<LineaDelPedido> lineas;

  /// Cuándo se armó (hora de este teléfono) o, si el servidor ya lo recibió, cuándo **llegó**.
  final DateTime fecha;

  /// Lo que pidió (centavos): la estimación local hasta que el servidor lo suma.
  final int montoCentavos;

  /// El servidor avisó que con este pedido la deuda pasaba el límite de la campaña.
  final bool excedeLimite;

  /// Lo que autorizó el coordinador (centavos); `null` mientras no decidió.
  final int? montoAutorizadoCentavos;

  /// El motivo del coordinador si no lo autorizó.
  final String? motivoRechazo;

  /// El «Pedido #231» del servidor; `null` hasta que el pedido llega.
  final int? numero;

  final Auditoria auditoria;

  /// Lo que muestra el pedido: lo autorizado si ya se decidió, y si no lo pedido.
  int get montoVigenteCentavos => montoAutorizadoCentavos ?? montoCentavos;

  /// Cuántas unidades lleva (la suma de las líneas vigentes).
  int get unidades => lineas.fold(0, (s, l) => s + l.cantidadVigente);

  /// El pedido llegó al servidor (le puso número).
  bool get llego => numero != null;

  @override
  List<Object?> get props => [
    id,
    colportorId,
    estado,
    lineas,
    fecha,
    montoCentavos,
    excedeLimite,
    montoAutorizadoCentavos,
    motivoRechazo,
    numero,
    auditoria,
  ];
}

/// Lo que devuelve enviar un pedido.
final class PedidoEnviado extends Equatable {
  const PedidoEnviado({required this.pedido, this.yaEstaba = false});

  final Pedido pedido;

  /// El pedido ya estaba guardado con ese id (un segundo toque o un reintento): no se escribió nada.
  final bool yaEstaba;

  @override
  List<Object?> get props => [pedido, yaEstaba];
}

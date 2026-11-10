import 'package:equatable/equatable.dart';

/// Un libro (o revista) de un pedido y cuántos son.
final class LineaDePedido extends Equatable {
  const LineaDePedido({required this.nombre, required this.cantidad});

  final String nombre;
  final int cantidad;

  @override
  List<Object?> get props => [nombre, cantidad];
}

/// Un pedido a la casa editora que todavía tiene saldo (vista 33B·01): cuánto valió, cuánto se pagó
/// y cuánto falta. Todo en centavos.
final class PedidoConSaldo extends Equatable {
  const PedidoConSaldo({
    required this.pedidoId,
    required this.fechaPedido,
    required this.montoCentavos,
    required this.pagadoCentavos,
    required this.saldoCentavos,
    required this.lineas,
  });

  final String pedidoId;

  /// Cuándo llegó el pedido al servidor (UTC).
  final DateTime fechaPedido;

  /// Lo que el pedido suma a la deuda.
  final int montoCentavos;

  /// Lo que ya cubrieron los depósitos validados: pagan primero el pedido más viejo (decisión de
  /// Cristian, 03/11, «Pagado ped.»).
  final int pagadoCentavos;

  /// Lo que falta del pedido.
  final int saldoCentavos;

  /// Los productos del pedido, por nombre.
  final List<LineaDePedido> lineas;

  @override
  List<Object?> get props => [
    pedidoId,
    fechaPedido,
    montoCentavos,
    pagadoCentavos,
    saldoCentavos,
    lineas,
  ];
}

/// La deuda del colportor con la casa editora tal como la contó el servidor (HU-CTA-002, vista 33B).
///
/// La cuenta se hace en un solo lugar, el servidor: el teléfono solo la muestra y guarda la última
/// respuesta. Todo en centavos.
final class DeudaConLaCasa extends Equatable {
  const DeudaConLaCasa({
    required this.deudaTotalCentavos,
    required this.sumaDeSaldosCentavos,
    required this.depositosValidadosCentavos,
    required this.pedidos,
    this.deudaHace7DiasCentavos,
  });

  /// La deuda real. Negativa = quedó a favor (se pagó de más): se descuenta de la próxima deuda del
  /// mismo concepto (decisión de Cristian, 25/10, «Pago de más»).
  final int deudaTotalCentavos;

  /// La suma de los saldos de los pedidos. Si no da [deudaTotalCentavos], algo más movió la deuda sin
  /// ser un pedido ni un depósito (una transferencia, el alquiler, un cobro con tarjeta).
  final int sumaDeSaldosCentavos;

  /// Lo que sumaron los depósitos validados a la casa editora.
  final int depositosValidadosCentavos;

  /// Solo los pedidos con saldo, el más viejo primero.
  final List<PedidoConSaldo> pedidos;

  /// La deuda que figuraba hace 7 días (7 × 24 h), la que registró el servidor (backend-supabase 0168).
  /// `null` = el servidor no tiene registro de esa fecha (cuenta nueva, o menos de una semana desde que
  /// empezó a registrarlas): no es «igual», es «no se puede comparar». Negativa = estaba a favor.
  final int? deudaHace7DiasCentavos;

  /// Cuánto cambió la deuda contra la semana pasada: negativo = bajó, positivo = subió, 0 = igual.
  /// `null` si no hay con qué comparar. Es la cuenta del servidor sobre su propio historial:
  /// «deuda_total − deuda_hace_7_dias» (decisión de Cristian, 04/11, «Del servidor, todo cuenta»).
  int? get variacionCentavos {
    final hace7 = deudaHace7DiasCentavos;
    return hace7 == null ? null : deudaTotalCentavos - hace7;
  }

  /// No debe nada y nada la explica (33B·02).
  bool get sinDeuda => deudaTotalCentavos == 0 && pedidos.isEmpty;

  /// Pagó de más.
  bool get aFavor => deudaTotalCentavos < 0;

  /// Los saldos de arriba no explican el total, y la pantalla lo aclara. Quedar a favor sin saldos
  /// ya se explica solo.
  bool get saldosNoDanElTotal =>
      sumaDeSaldosCentavos != deudaTotalCentavos && !(aFavor && sumaDeSaldosCentavos == 0);

  @override
  List<Object?> get props => [
    deudaTotalCentavos,
    sumaDeSaldosCentavos,
    depositosValidadosCentavos,
    pedidos,
    deudaHace7DiasCentavos,
  ];
}

/// La última respuesta del servidor y cuándo llegó (hora del teléfono, UTC). Es lo que se guarda para
/// ver la deuda sin conexión.
final class LecturaDeLaDeuda extends Equatable {
  const LecturaDeLaDeuda({required this.deuda, required this.leidaEn});

  final DeudaConLaCasa deuda;
  final DateTime leidaEn;

  @override
  List<Object?> get props => [deuda, leidaEn];
}

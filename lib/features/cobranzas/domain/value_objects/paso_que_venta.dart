import 'package:equatable/equatable.dart';

import '../entities/venta_con_saldo.dart';

/// Qué sigue de «$ Cobrar» según las ventas con saldo de la persona (vista 39, C·08 «¿Qué venta?»):
///
/// - [SinVentasConSaldo]: no hay nada para cobrar (la persona ya pagó todo mientras la hoja estaba
///   abierta); se dice, no se abre el cobro.
/// - [UnaVentaConSaldo]: el paso de elegir **se salta** y se cobra esa venta («Con una sola venta con
///   saldo se salta», canvas C·08).
/// - [VariasVentasConSaldo]: la lista, con la más vieja elegida.
sealed class PasoQueVenta extends Equatable {
  const PasoQueVenta();

  /// El paso que corresponde a [ventas]. Las que ya no deben nada no cuentan: aunque quien lee ya las
  /// filtra, una venta pagada no se ofrece para cobrar.
  static PasoQueVenta de(Iterable<VentaConSaldo> ventas) {
    final conSaldo = ventas.where((v) => v.tieneSaldo).toList(growable: false);
    return switch (conSaldo.length) {
      0 => const SinVentasConSaldo(),
      1 => UnaVentaConSaldo(conSaldo.single),
      _ => VariasVentasConSaldo(conSaldo),
    };
  }
}

final class SinVentasConSaldo extends PasoQueVenta {
  const SinVentasConSaldo();

  @override
  List<Object?> get props => const [];
}

final class UnaVentaConSaldo extends PasoQueVenta {
  const UnaVentaConSaldo(this.venta);

  final VentaConSaldo venta;

  @override
  List<Object?> get props => [venta];
}

final class VariasVentasConSaldo extends PasoQueVenta {
  const VariasVentasConSaldo(this.ventas);

  /// En el orden en que llegan (la más vieja primero); la primera viene elegida.
  final List<VentaConSaldo> ventas;

  @override
  List<Object?> get props => [ventas];
}

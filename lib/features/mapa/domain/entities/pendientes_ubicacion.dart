import 'package:equatable/equatable.dart';

/// Lo que una ubicación tiene abierto y que la baja deja sin poder operar (HU-UBI-005, "Bloqueo").
final class PendientesUbicacion extends Equatable {
  const PendientesUbicacion({
    this.visitasPendientes = 0,
    this.ventasConSaldo = 0,
    this.cobranzasActivas = 0,
  });

  static const ninguno = PendientesUbicacion();

  final int visitasPendientes;
  final int ventasConSaldo;

  /// Cobros sin cerrar.
  final int cobranzasActivas;

  bool get hayPendientes => visitasPendientes > 0 || ventasConSaldo > 0 || cobranzasActivas > 0;

  /// El resumen de la doble confirmación, una frase por cada pendiente. El de cobranzas es el
  /// texto literal del criterio de aceptación (con "2 cobranzas activas"); los otros dos son
  /// propios, para confirmar con Cristian.
  List<String> get resumen => [
    if (cobranzasActivas > 0)
      'Esta ubicación tiene $cobranzasActivas ${cobranzasActivas == 1 ? 'cobranza activa' : 'cobranzas activas'}. '
          'Si la das de baja, no podrás registrar nuevos cobros, pero el historial se conserva.',
    if (ventasConSaldo > 0)
      'Esta ubicación tiene $ventasConSaldo ${ventasConSaldo == 1 ? 'venta con saldo pendiente' : 'ventas con saldo pendiente'}. '
          'Si la das de baja, el saldo y el historial se conservan.',
    if (visitasPendientes > 0)
      'Esta ubicación tiene $visitasPendientes ${visitasPendientes == 1 ? 'visita pendiente' : 'visitas pendientes'}. '
          'Si la das de baja, no podrás registrar nuevas visitas, pero el historial se conserva.',
  ];

  @override
  List<Object?> get props => [visitasPendientes, ventasConSaldo, cobranzasActivas];
}

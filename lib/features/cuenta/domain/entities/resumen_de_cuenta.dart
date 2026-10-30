import 'package:equatable/equatable.dart';

/// Una cifra de Mi Cuenta: lo que hay ahora y cuánto cambió contra la semana pasada.
///
/// Todo en centavos. Es una lectura del teléfono: nunca viaja al servidor ni lleva el dato de nadie.
final class CifraDeCuenta extends Equatable {
  const CifraDeCuenta({required this.totalCentavos, this.variacionCentavos});

  /// Lo que hay ahora; nunca negativo.
  final int totalCentavos;

  /// Cuánto subió (positivo) o bajó (negativo) contra el mismo momento de hace 7 días; 0 si quedó
  /// igual. `null` cuando no hay datos de la semana anterior (cuenta nueva, 33A-04): no es «igual»,
  /// es «no se puede comparar».
  final int? variacionCentavos;

  /// Hay con qué comparar contra la semana pasada.
  bool get tieneComparacion => variacionCentavos != null;

  @override
  List<Object?> get props => [totalCentavos, variacionCentavos];
}

/// El resumen de Mi Cuenta del colportor (HU-CTA-001, vista 33A).
///
/// En V1 lleva **En mano** y **Por cobrar**, las dos cifras que salen del teléfono. «Deuda con la
/// casa editora» llega con los pedidos (decisión de Cristian, 23/10, «Deuda casa»: HU-CTA-002 es V2)
/// y «Depositado» espera que el teléfono sepa qué depósitos y tickets validó el coordinador.
final class ResumenDeCuenta extends Equatable {
  const ResumenDeCuenta({required this.enMano, required this.porCobrar});

  /// El efectivo cobrado que todavía no se depositó, menos lo que se devolvió a clientes en el
  /// momento (decisión del 30/10 en #431).
  final CifraDeCuenta enMano;

  /// Lo que le deben al colportor: la suma del saldo de sus ventas vivas (HU-COB-005).
  final CifraDeCuenta porCobrar;

  @override
  List<Object?> get props => [enMano, porCobrar];
}

import 'package:equatable/equatable.dart';

/// Cómo va la jornada contra la anterior (vista 21, 21J·01, 21J·02 y 21J·04; decisión del agente de
/// decisiones, 04/11, regla R3): casas visitadas y ventas, contra la última jornada cerrada de la
/// misma campaña. Los cobros no entran y el misionero no cuenta como venta (Cristian, 28/10, «Venta $ 0»).
class TendenciaDeLaJornada extends Equatable {
  const TendenciaDeLaJornada({
    required this.casasVisitadas,
    required this.ventas,
    this.casasVisitadasAntes,
    this.ventasAntes,
  });

  final int casasVisitadas;

  final int ventas;

  /// Lo mismo en la jornada anterior; `null` en la primera de la campaña (21J·04: sin tendencia).
  final int? casasVisitadasAntes;

  final int? ventasAntes;

  /// En la primera jornada de la campaña no hay contra qué comparar.
  bool get esPrimera => casasVisitadasAntes == null || ventasAntes == null;

  /// Lo que subió (positivo) o bajó (negativo) respecto de la anterior; `null` si es la primera.
  int? get diferenciaDeCasas => esPrimera ? null : casasVisitadas - casasVisitadasAntes!;

  int? get diferenciaDeVentas => esPrimera ? null : ventas - ventasAntes!;

  @override
  List<Object?> get props => [casasVisitadas, ventas, casasVisitadasAntes, ventasAntes];
}

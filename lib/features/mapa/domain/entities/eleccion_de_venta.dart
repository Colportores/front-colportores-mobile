import 'package:equatable/equatable.dart';

import 'persona_de_la_entrevista.dart';

/// Lo que entrega el paso «¿Con quién?» de «Vender» (vista 39, #661): a quién se le vende, o que ya no
/// queda a quién. `null` (fuera de este tipo) es «Volver» o cerrar sin elegir.
sealed class EleccionDeVenta extends Equatable {
  const EleccionDeVenta();
}

/// La venta es de [persona].
final class VenderA extends EleccionDeVenta {
  const VenderA(this.persona);

  final PersonaDeLaEntrevista persona;

  @override
  List<Object?> get props => [persona];
}

/// Mientras se elegía, las personas entrevistadas se dieron de baja: no hay a quién venderle. Quien
/// abrió el paso lo dice (qué pasó y qué hacer); la colportora no cerró nada.
final class NadieParaVender extends EleccionDeVenta {
  const NadieParaVender();

  @override
  List<Object?> get props => const [];
}

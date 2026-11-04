import 'package:equatable/equatable.dart';

/// Lo que el colportor depositó, separado por lo que dijo el coordinador (decisión «Acredita V1»,
/// 23/10): **«Depositado» suma solo lo validado** y lo que espera su validación va aparte. Un depósito
/// rechazado no suma a ninguno de los dos: volvió a estar «en mano».
///
/// Todo en centavos. Es una lectura del teléfono; no lleva el dato de nadie.
final class TotalesDeDepositos extends Equatable {
  const TotalesDeDepositos({required this.validadoCentavos, required this.porValidarCentavos});

  /// La suma de los depósitos que el coordinador validó.
  final int validadoCentavos;

  /// La suma de los depósitos registrados que todavía esperan su validación.
  final int porValidarCentavos;

  @override
  List<Object?> get props => [validadoCentavos, porValidarCentavos];
}

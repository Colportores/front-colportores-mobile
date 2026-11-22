import 'package:equatable/equatable.dart';

import 'deposito.dart';

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

/// Un depósito que cuenta en «Depositado» o espera para contar (HU-CTA-003, vista 33C): lo que el
/// detalle de Mi plata lista debajo de la cifra. Un depósito rechazado no está acá.
///
/// No lleva el motivo ni el coordinador: es lo que se ve en una fila, y nada más.
final class DepositoDeLaLista extends Equatable {
  const DepositoDeLaLista({
    required this.montoCentavos,
    required this.fecha,
    required this.destino,
    required this.concepto,
    required this.validado,
  });

  /// Lo depositado, en centavos.
  final int montoCentavos;

  /// Cuándo se depositó (UTC).
  final DateTime fecha;

  final DestinoDeDeposito destino;
  final ConceptoDeDeposito concepto;

  /// El coordinador lo validó; `false` = todavía por validar.
  final bool validado;

  @override
  List<Object?> get props => [montoCentavos, fecha, destino, concepto, validado];
}

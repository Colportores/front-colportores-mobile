import 'package:equatable/equatable.dart';

import 'espacio.dart';

/// Cómo terminó un pedido de baja de espacio (HU-UBI-007) que no fue un error.
sealed class ResultadoBajaEspacio extends Equatable {
  const ResultadoBajaEspacio();
}

/// El espacio quedó dado de baja (o ya lo estaba: repetir el pedido no hace nada).
final class BajaRealizada extends ResultadoBajaEspacio {
  const BajaRealizada(this.espacio);

  final Espacio espacio;

  @override
  List<Object?> get props => [espacio];
}

/// El espacio tiene personas y el colportor todavía no confirmó: no se dio de baja nada. La
/// pantalla muestra [aviso] y, si sigue, repite el pedido con `confirmaConPersonas: true`.
final class BajaRequiereConfirmacion extends ResultadoBajaEspacio {
  const BajaRequiereConfirmacion({required this.personas});

  final int personas;

  /// Texto literal del criterio de aceptación "Baja de espacio con personas".
  String get aviso =>
      'Este espacio tiene $personas personas. Sus datos se conservarán pero el espacio quedará '
      'marcado como baja.';

  @override
  List<Object?> get props => [personas];
}

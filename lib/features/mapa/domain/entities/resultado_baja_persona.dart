import 'package:equatable/equatable.dart';

import '../services/cuenta_de_persona.dart';
import 'persona.dart';

/// Cómo terminó el pedido de dar de baja a una persona (HU-UBI-011).
sealed class ResultadoBajaPersona extends Equatable {
  const ResultadoBajaPersona();

  /// Lleva datos personales: ver `Persona.stringify`.
  @override
  bool? get stringify => false;
}

/// La persona quedó de baja en el teléfono (o ya lo estaba: un doble toque).
final class PersonaDadaDeBaja extends ResultadoBajaPersona {
  const PersonaDadaDeBaja(this.persona);

  final Persona persona;

  @override
  List<Object?> get props => [persona];
}

/// Debe algo y nadie confirmó todavía: no se escribió nada. La pantalla muestra el resumen [cuenta] y
/// pide la doble confirmación (canvas 32D·02 y 32D·03).
final class BajaPersonaRequiereConfirmacion extends ResultadoBajaPersona {
  const BajaPersonaRequiereConfirmacion(this.cuenta);

  final ResumenCuentaPersona cuenta;

  @override
  List<Object?> get props => [cuenta];
}

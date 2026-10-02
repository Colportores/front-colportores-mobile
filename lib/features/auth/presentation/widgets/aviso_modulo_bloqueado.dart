import 'package:flutter/material.dart';

import '../../domain/entities/estado_cuenta.dart';

/// Lo que se le dice al colportor que toca un módulo bloqueado de la barra inferior (vista 18).
abstract final class TextosModuloBloqueado {
  /// Propuesta del diseño (18, nota al pie).
  static const pendiente = 'Disponible cuando tu coordinador te asigne a una campaña.';

  /// Literal de HU-AUTH-008 para la cuenta suspendida.
  static const suspendida = 'Tu cuenta está suspendida. Contactá al administrador.';

  static String para(EstadoCuenta? estado) =>
      estado == EstadoCuenta.suspendida ? suspendida : pendiente;
}

/// Avisa por qué el módulo no está disponible, sin acumular avisos si se toca varias veces.
void avisarModuloBloqueado(BuildContext context, EstadoCuenta? estado) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('modulo_bloqueado_aviso'),
        content: Text(TextosModuloBloqueado.para(estado)),
      ),
    );
}

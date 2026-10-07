import 'package:flutter/material.dart';

import '../../domain/entities/estado_cuenta.dart';
import '../pages/esperando_asignacion_page.dart';

/// Lo que se le dice al colportor que toca un módulo bloqueado de la barra inferior (vista 18).
abstract final class TextosModuloBloqueado {
  /// Propuesta del diseño (18, nota al pie).
  static const pendiente = 'Disponible cuando tu coordinador te asigne a una campaña.';

  /// Literal de HU-AUTH-008 para la cuenta suspendida.
  static const suspendida = 'Tu cuenta está suspendida. Contactá al administrador.';

  /// El aviso para [estado]. Con [estado] `null` (nunca se pudo consultar la cuenta) la app no
  /// sabe si está pendiente: repite el aviso de la pantalla para la misma causa (decisión del
  /// orquestador, 02/10, #278): el de sin conexión si [sinConexion], el del error del servidor si
  /// no.
  static String para(EstadoCuenta? estado, {bool sinConexion = false}) => switch (estado) {
    EstadoCuenta.suspendida => suspendida,
    null =>
      sinConexion ? TextosEsperaAsignacion.sinConexionSinEstado : TextosEsperaAsignacion.sinEstado,
    _ => pendiente,
  };
}

/// Avisa por qué el módulo no está disponible, sin acumular avisos si se toca varias veces.
///
/// Con [estado] `null` el aviso es el de la causa por la que no se conoce ([sinConexion] o error
/// del servidor), ver [TextosModuloBloqueado.para].
void avisarModuloBloqueado(BuildContext context, EstadoCuenta? estado, {bool sinConexion = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('modulo_bloqueado_aviso'),
        content: Text(TextosModuloBloqueado.para(estado, sinConexion: sinConexion)),
      ),
    );
}

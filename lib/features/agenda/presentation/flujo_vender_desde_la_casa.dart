import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mapa/presentation/providers/hoja_casa_providers.dart'
    show ContextoDeVenta, VentaRegistradaEnLaCasa;
import 'widgets/flujo_entrevista.dart';
import 'widgets/hoja_termino_entrevista.dart';

/// «Vender» de «¿Qué pasó?» (vista 39, decisión de Cristian del 04/11, «Vender desde el mapa»): lo que
/// enchufa `venderDesdeLaCasaProvider`. Abre la venta (vista 27) con la casa y la persona de la última
/// entrevista dada ya puestas y sigue como «Sí, registrar la venta»: [FlujoEntrevista.venderDesdeLaCasa].
///
/// Devuelve [VentaRegistradaEnLaCasa] si la venta se guardó (la hoja de la casa sigue abierta, R·08) y
/// `false` si no (no cambió nada).
abstract final class FlujoVenderDesdeLaCasa {
  static Future<Object?> abrir(
    BuildContext context,
    ContextoDeVenta datos, {
    required String? colportorId,
  }) async {
    final colportor = colportorId?.trim();
    if (colportor == null || colportor.isEmpty) return false;
    final salida = await FlujoEntrevista.venderDesdeLaCasa(
      context,
      ProviderScope.containerOf(context, listen: false),
      colportorId: colportor,
      espacioId: datos.espacioId,
      espacioPersonaId: datos.espacioPersonaId,
    );
    return salida is VentaGuardadaEnLaEntrevista ? const VentaRegistradaEnLaCasa() : false;
  }
}

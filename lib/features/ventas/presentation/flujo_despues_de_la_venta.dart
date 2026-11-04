import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cobranzas/presentation/providers/cobranzas_providers.dart'
    show saldoPendienteRepositoryProvider;
import '../domain/entities/nueva_venta.dart' show VentaGuardada;
import 'pages/venta_registrada_page.dart';
import 'providers/ventas_providers.dart' show ContextoDeCobroDeLaVenta;

/// Lo que viene después de guardar una venta, compartido por quien la abre desde la entrevista de la
/// casa (#428) y desde la pestaña Ventas (#546): la pantalla «Venta registrada: ¿y ahora?» (27A·14) y
/// el cobro (vista 28).
abstract final class FlujoDespuesDeLaVenta {
  /// 27A·14 «Venta registrada: ¿y ahora?». Sin salida del atrás: se sale con «Listo» (o «Terminar sin
  /// nada») y es lo que elige lo que se hace después. `null` = terminó sin pedir nada.
  static Future<SeguimientoDeLaVenta?> ventaRegistrada(
    BuildContext context, {
    required VentaGuardada guardada,
    required String nombre,
    required bool conCobro,
  }) => Navigator.of(context).push<SeguimientoDeLaVenta>(
    MaterialPageRoute(
      builder: (ruta) => VentaRegistradaPage(
        guardada: guardada,
        nombreDelCliente: nombre,
        conCobro: conCobro,
        alContinuar: (seguimiento) => Navigator.of(ruta).pop(seguimiento),
        alTerminar: () => Navigator.of(ruta).pop(),
      ),
    ),
  );

  /// «Cobrar ahora»: abre el cobro (vista 28) y devuelve lo que quedó sin cobrar, en centavos. Si no
  /// se cobró, o no se puede leer cuánto, es el total de la venta: preguntar «¿Cuándo volvés a cobrar?»
  /// de más es mejor que dejar una deuda sin cita.
  static Future<int> cobrarAhora(
    ProviderContainer ref,
    Future<bool> Function(ContextoDeCobroDeLaVenta) cobrar, {
    required VentaGuardada guardada,
    required String espacioId,
    required String espacioPersonaId,
    required String colportorId,
  }) async {
    final total = guardada.totalCentavos;
    try {
      final cobrado = await cobrar((
        ventaId: guardada.venta.id,
        espacioId: espacioId,
        espacioPersonaId: espacioPersonaId,
        colportorId: colportorId,
      ));
      if (!cobrado) return total;
      final venta = await ref
          .read(saldoPendienteRepositoryProvider)
          .observarVenta(guardada.venta.id)
          .first
          .timeout(const Duration(seconds: 2));
      return venta?.saldoCentavos ?? total;
    } on Object {
      return total;
    }
  }
}

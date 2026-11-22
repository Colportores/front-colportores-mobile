import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../auth/presentation/providers/sesion_notifier.dart';
import '../../cobranzas/presentation/pages/cuotas_de_la_venta_page.dart';
import 'providers/historial_de_la_casa_providers.dart';

/// «Ver la venta» del detalle de una venta del Historial de la casa (vista 39, C·04) abre las cuotas
/// de ESA venta (`CuotasDeLaVentaPage`, vista 30 A: el resumen, el plan o «sin saldo»), la misma
/// pantalla que abre la venta desde el detalle de la Agenda (decisión del 10/11, P2 de #446). Es lo
/// que enchufa [verVentaDesdeLaCasaProvider].
///
/// La pantalla se empuja sobre el navegador de la app: la hoja de la casa queda abajo y al volver
/// sigue abierta. Todo se lee del teléfono: funciona igual sin conexión.
///
/// Lanza si no hay a dónde abrir (sin navegador o sin sesión iniciada): la pestaña lo dice con su
/// propio aviso («No pudimos abrir la venta. Probá de nuevo.») y la fila vuelve a quedar habilitada.
abstract final class FlujoVerVentaDesdeLaCasa {
  /// Abre las cuotas de [venta] y espera a que se cierre. [colportorId] es el usuario con la sesión
  /// iniciada. `true` si se armó o se modificó el plan mientras estuvo abierta.
  static Future<bool> abrir(
    BuildContext context,
    ContextoDeVentaDeLaCasa venta, {
    required String? colportorId,
  }) {
    final colportor = colportorId?.trim() ?? '';
    if (colportor.isEmpty) {
      throw StateError('Las cuotas de la venta necesitan una sesión iniciada');
    }
    return CuotasDeLaVentaPage.abrir(
      context,
      ventaId: venta.ventaId,
      colportorId: colportor,
      espacioId: venta.espacioId,
      espacioPersonaId: venta.espacioPersonaId,
    );
  }

  /// El enganche de [verVentaDesdeLaCasaProvider] sobre el navegador de la app [navegador], con el
  /// colportor de la sesión. `main.dart` lo suma a los overrides de la app; un test, también.
  static Override enganche(GlobalKey<NavigatorState> navegador) =>
      verVentaDesdeLaCasaProvider.overrideWith(
        (ref) => (venta) {
          final contexto = navegador.currentContext;
          if (contexto == null) throw StateError('No hay navegador donde abrir la venta');
          return abrir(contexto, venta, colportorId: ref.read(sesionProvider).value?.usuarioId);
        },
      );
}

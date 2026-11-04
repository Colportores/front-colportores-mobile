import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../auth/presentation/providers/sesion_notifier.dart';
import '../../cobranzas/presentation/pages/cuotas_de_la_venta_page.dart';
import '../../notificaciones/domain/entities/destino_notificacion.dart';
import '../../notificaciones/presentation/providers/historial_notificaciones_providers.dart';
import '../domain/entities/agenda.dart';
import '../domain/repositories/agenda_repository.dart';
import 'pages/detalle_agenda_page.dart';
import 'providers/agenda_providers.dart';
import 'providers/consulta_agenda_providers.dart';
import 'providers/recordatorios_providers.dart';

/// Abre el detalle de una agenda (vista 23, 23C·01) desde cada lugar que lleva a él.
abstract final class FlujoDetalleAgenda {
  /// Abre el detalle de [agendaId] encima de [context]. Sin usuario con la sesión iniciada no hay a
  /// nombre de quién mostrarlo y no hace nada.
  static Future<void> abrir(
    BuildContext context, {
    required String agendaId,
    required String? colportorId,
  }) async {
    final colportor = colportorId?.trim() ?? '';
    if (colportor.isEmpty || agendaId.trim().isEmpty) return;
    // Un aviso viejo («Guardado»…) taparía los botones de la pantalla nueva.
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    await DetalleAgendaPage.abrir(context, agendaId: agendaId, colportorId: colportor);
  }

  /// Abre lo que lleva un **aviso** de la agenda (HU-COB-004, #580): si la cita es una cuota del plan
  /// de una venta —una cobranza con su `venta_id` y su `monto_previsto`—, las cuotas de esa venta
  /// (30A-06, `00 Navegacion`: «Notificación o agenda de cobranza»); si no, el detalle de la agenda.
  ///
  /// Si no se puede leer la agenda (falla, o ya no está en el teléfono) se abre el detalle, que dice
  /// qué pasó y ofrece «Reintentar»: tocar un aviso nunca queda sin respuesta. La push de cuota
  /// vencida (HU-NOT-003, #187) usa este mismo destino (`agenda/<id>` de la cobranza).
  static Future<void> abrirAviso(
    BuildContext context, {
    required AgendaRepository agendas,
    required String agendaId,
    required String? colportorId,
  }) async {
    final colportor = colportorId?.trim() ?? '';
    if (colportor.isEmpty || agendaId.trim().isEmpty) return;
    Agenda? agenda;
    try {
      final lectura = await agendas.obtenerDetalle(agendaId);
      agenda = lectura.fold((_) => null, (detalle) => detalle?.agenda);
    } on Object {
      agenda = null;
    }
    if (!context.mounted) return;
    final ventaId = agenda?.ventaId;
    if (agenda == null || !agenda.esCuota || ventaId == null) {
      await abrir(context, agendaId: agendaId, colportorId: colportor);
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    await CuotasDeLaVentaPage.abrir(
      context,
      ventaId: ventaId,
      colportorId: colportor,
      espacioId: agenda.espacioId,
      espacioPersonaId: agenda.espacioPersonaId,
    );
  }

  /// Los enganches que llevan al detalle de una agenda, sobre el navegador de la app [navegador]:
  ///
  /// - **tocar un recordatorio** (con la app cerrada, en segundo plano o abierta) →
  ///   [abridorDetalleAgendaProvider];
  /// - **tocar un aviso del centro de notificaciones** → [abridorDestinoNotificacionProvider];
  /// - **tocar una fila de la pestaña Agenda** → [abrirDetalleDeAgendaProvider].
  ///
  /// Los dos primeros son avisos: si la cita es una cuota abren las cuotas ([abrirAviso]). La fila
  /// de la pestaña Agenda abre el detalle, que tiene «Ver las cuotas».
  ///
  /// `main.dart` los suma a los overrides de la app; un test de la app entera, también.
  static List<Override> enganches(GlobalKey<NavigatorState> navegador) => [
    abridorDetalleAgendaProvider.overrideWith(
      (ref) =>
          (agendaId) => _avisoDesdeElNavegador(ref, navegador, agendaId),
    ),
    abrirDetalleDeAgendaProvider.overrideWith(
      (ref) =>
          (agendaId) => _desdeElNavegador(ref, navegador, agendaId),
    ),
    abridorDestinoNotificacionProvider.overrideWith(
      (ref) => (context, destino) async {
        switch (destino) {
          case DestinoAgenda(:final agendaId):
            await abrirAviso(
              context,
              agendas: ref.read(agendaRepositoryProvider),
              agendaId: agendaId,
              colportorId: ref.read(sesionProvider).value?.usuarioId,
            );
        }
      },
    ),
  ];

  static Future<void> _avisoDesdeElNavegador(
    Ref ref,
    GlobalKey<NavigatorState> navegador,
    String agendaId,
  ) async {
    final contexto = navegador.currentContext;
    if (contexto == null) return;
    await abrirAviso(
      contexto,
      agendas: ref.read(agendaRepositoryProvider),
      agendaId: agendaId,
      colportorId: ref.read(sesionProvider).value?.usuarioId,
    );
  }

  static Future<void> _desdeElNavegador(
    Ref ref,
    GlobalKey<NavigatorState> navegador,
    String agendaId,
  ) async {
    final contexto = navegador.currentContext;
    if (contexto == null) return;
    await abrir(
      contexto,
      agendaId: agendaId,
      colportorId: ref.read(sesionProvider).value?.usuarioId,
    );
  }
}

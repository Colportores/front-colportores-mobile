import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../auth/presentation/providers/sesion_notifier.dart';
import '../../notificaciones/domain/entities/destino_notificacion.dart';
import '../../notificaciones/presentation/providers/historial_notificaciones_providers.dart';
import 'pages/detalle_agenda_page.dart';
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

  /// Los enganches que llevan al detalle de una agenda, sobre el navegador de la app [navegador]:
  ///
  /// - **tocar un recordatorio** (con la app cerrada, en segundo plano o abierta) →
  ///   [abridorDetalleAgendaProvider];
  /// - **tocar un aviso del centro de notificaciones** → [abridorDestinoNotificacionProvider];
  /// - **tocar una fila de la pestaña Agenda** → [abrirDetalleDeAgendaProvider].
  ///
  /// `main.dart` los suma a los overrides de la app; un test de la app entera, también.
  static List<Override> enganches(GlobalKey<NavigatorState> navegador) => [
    abridorDetalleAgendaProvider.overrideWith(
      (ref) =>
          (agendaId) => _desdeElNavegador(ref, navegador, agendaId),
    ),
    abrirDetalleDeAgendaProvider.overrideWith(
      (ref) =>
          (agendaId) => _desdeElNavegador(ref, navegador, agendaId),
    ),
    abridorDestinoNotificacionProvider.overrideWith(
      (ref) => (context, destino) async {
        switch (destino) {
          case DestinoAgenda(:final agendaId):
            await abrir(
              context,
              agendaId: agendaId,
              colportorId: ref.read(sesionProvider).value?.usuarioId,
            );
        }
      },
    ),
  ];

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

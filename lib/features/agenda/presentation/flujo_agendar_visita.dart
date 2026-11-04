import 'package:flutter/material.dart';

import '../domain/entities/tipo_agenda.dart';
import 'pages/agendar_visita_page.dart';

/// «Agendar una visita» como la abre el resto de la app (vista 39, «Programar entrevista», y la
/// pestaña Agenda): abre [AgendarVisitaPage] y, si se agendó, deja el aviso de éxito en el
/// `ScaffoldMessenger` de quien la abrió (23A·05), que sigue a la vista cuando la pantalla se cierra.
abstract final class FlujoAgendarVisita {
  /// Devuelve `true` si la visita quedó agendada (quien la abrió se actualiza: la casa cambió de color).
  static Future<bool> abrir(
    BuildContext context, {
    required String espacioId,
    String? espacioPersonaId,
    required String? colportorId,
    TipoAgenda tipo = TipoAgenda.entrevista,
  }) async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final colportor = colportorId?.trim() ?? '';
    // Sin usuario no hay a nombre de quién agendar.
    if (colportor.isEmpty) return false;
    // Un aviso viejo («Guardado»…) taparía el botón de la pantalla nueva.
    mensajero?.clearSnackBars();
    final guardada = await AgendarVisitaPage.abrir(
      context,
      espacioId: espacioId,
      espacioPersonaId: espacioPersonaId,
      colportorId: colportor,
      tipo: tipo,
    );
    if (guardada == null) return false;
    mensajero
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(guardada.aviso)));
    return true;
  }
}

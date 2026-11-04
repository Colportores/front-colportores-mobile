import 'package:flutter/material.dart';

import '../../agenda/presentation/flujo_agendar_visita.dart';
import 'pages/elegir_casa_para_agendar_page.dart';
import 'widgets/hoja_con_quien.dart';

/// «+ Agendar» de la pestaña Agenda (vista 23B, #568): no viene de ninguna casa, así que primero se
/// elige (la lista de ubicaciones, vista 05, en modo selección), después se pregunta con quién es la
/// cita (`¿Con quién?`, la misma de «Programar entrevista»: una persona, varias o «Sin persona») y
/// se abre «Agendar visita» (23A·01) con la casa y la persona ya puestas.
abstract final class FlujoAgendarDesdeLaAgenda {
  /// Devuelve `true` si la visita quedó agendada. `false` si se volvió atrás en cualquier paso, o si
  /// no hay un usuario con la sesión iniciada (no hay a nombre de quién agendar).
  ///
  /// [dia] es el día del rótulo desde el que se tocó «+ Agendar» (23B·01): si es futuro, el formulario
  /// abre con ese día; `null` (o hoy, o un día pasado, o las atrasadas) con la fecha de siempre.
  static Future<bool> abrir(
    BuildContext context, {
    required String? colportorId,
    DateTime? dia,
  }) async {
    final colportor = colportorId?.trim() ?? '';
    if (colportor.isEmpty) return false;
    final casa = await ElegirCasaParaAgendarPage.abrir(context, colportorId: colportor);
    if (casa == null || !context.mounted) return false;
    final eleccion = await mostrarHojaConQuienParaProgramar(
      context,
      espacioId: casa.espacioId,
      colportorId: colportor,
    );
    if (eleccion == null || !context.mounted) return false;
    return FlujoAgendarVisita.abrir(
      context,
      espacioId: casa.espacioId,
      espacioPersonaId: eleccion.espacioPersonaId,
      colportorId: colportor,
      diaInicial: dia,
    );
  }
}

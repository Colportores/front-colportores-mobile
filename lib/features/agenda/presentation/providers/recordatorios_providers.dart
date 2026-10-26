import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/recordatorios/fakes/recordatorios_en_memoria.dart';
import '../../domain/services/recordatorios.dart';

// Cableado de los recordatorios locales de las visitas (HU-NOT-002). Los casos de uso de la agenda
// (HU-VIS-001 a 004) piden [recordatoriosProvider]; `main.dart` lo reemplaza con
// `RecordatoriosLocales` sobre el plugin del teléfono.

final _recordatoriosEnMemoriaProvider = Provider<RecordatoriosEnMemoria>(
  (ref) => RecordatoriosEnMemoria(),
);

/// Programa, reprograma y cancela el aviso de cada visita. El default es el fake en memoria: lo usan
/// los tests y la app sin el plugin, y ninguna prueba toca el teléfono sin que se lo pidan.
final recordatoriosProvider = Provider<Recordatorios>(
  (ref) => ref.watch(_recordatoriosEnMemoriaProvider),
);

/// Los recordatorios que la persona toca. Es el mismo objeto que [recordatoriosProvider].
final toquesDeRecordatoriosProvider = Provider<ToquesDeRecordatorios>(
  (ref) => ref.watch(_recordatoriosEnMemoriaProvider),
);

/// Abre el detalle de la visita [agendaId] (vista 23, 23C·01). Es el enganche de la vista 23: hasta
/// que exista esa pantalla no hace nada y tocar un recordatorio solo abre la app. La pantalla del
/// detalle lo reemplaza con su navegación.
final abridorDetalleAgendaProvider = Provider<void Function(String agendaId)>(
  (ref) =>
      (agendaId) => AppLogger.instance.info(
        LogModulo.agenda,
        'RECORDATORIO_TOCADO',
        'se tocó un recordatorio y todavía no hay detalle de la visita',
        {'agenda_id': agendaId},
      ),
);

/// Lleva cada recordatorio tocado a [abridorDetalleAgendaProvider]: el que se tocó mientras la app
/// no escuchaba (la abrió el aviso, o estaba en el ingreso) sale apenas alguien lo mira, una sola
/// vez; los siguientes, en el momento. Lo mira la pantalla principal (`_Principal`, en `app.dart`):
/// sin sesión no hay a dónde ir.
final aperturasDesdeRecordatorioProvider = Provider.autoDispose<void>((ref) {
  final toques = ref.watch(toquesDeRecordatoriosProvider);

  void abrir(String agendaId) {
    if (!ref.mounted) return;
    try {
      ref.read(abridorDetalleAgendaProvider)(agendaId);
    } on Object catch (e, st) {
      AppLogger.instance.error(
        LogModulo.agenda,
        'RECORDATORIO_ABRIR',
        'no se pudo abrir el detalle de la visita',
        {'agenda_id': agendaId, 'error': e.runtimeType.toString()},
        e,
        st,
      );
    }
  }

  final suscripcion = toques.agendasTocadas.listen(abrir);
  ref.onDispose(suscripcion.cancel);
  unawaited(
    toques.tomarAgendaPendiente().then((agendaId) {
      if (agendaId != null) abrir(agendaId);
    }),
  );
});

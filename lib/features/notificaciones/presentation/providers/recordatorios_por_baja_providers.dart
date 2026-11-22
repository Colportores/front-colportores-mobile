import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../agenda/presentation/providers/agenda_providers.dart';
import '../../../agenda/presentation/providers/recordatorios_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../data/datasources/agendas_para_recordar_drift.dart';
import '../../domain/repositories/preferencias_recordatorios_repository.dart';
import '../../domain/services/conciliador_recordatorios_ocultos.dart';

// Cableado de «mientras la agenda está oculta tampoco suena su recordatorio» (HU-VIS-002, «Agenda
// baja», regla R7): las agendas de una casa o un depto dados de baja pierden el aviso, y lo recuperan
// si se reactivan.

/// Las agendas pendientes de la DB local, en vivo y con las ocultas marcadas. `null` sin DB abierta.
final agendasObservablesParaRecordarProvider = Provider<AgendasObservablesParaRecordar?>((ref) {
  final db = ref.watch(dbLocalProvider);
  return db == null ? null : AgendasParaRecordarDrift(db);
});

/// Saca el recordatorio de la agenda que se oculta y lo devuelve cuando vuelve. Lo mira la pantalla
/// principal (`_Principal`, en `app.dart`): sin sesión ni DB abierta no hay agendas que mirar.
final recordatoriosPorBajaProvider = Provider.autoDispose<void>((ref) {
  final fuente = ref.watch(agendasObservablesParaRecordarProvider);
  final colportorId = ref.watch(sesionProvider.select((s) => s.value?.usuarioId));
  if (fuente == null || colportorId == null) return;
  final conciliador = ConciliadorRecordatoriosOcultos(ref.watch(recordatoriosProvider));
  final suscripcion = fuente
      .observarPendientes(colportorId: colportorId, desde: ref.read(relojVisitaProvider)())
      .listen(
        (agendas) => unawaited(conciliador.aplicar(agendas)),
        onError: (Object e) => AppLogger.instance.error(
          LogModulo.agenda,
          'RECORDATORIOS_OCULTAS',
          'no se pudo revisar qué recordatorios ocultar',
          {'error': e.runtimeType.toString()},
        ),
      );
  ref.onDispose(suscripcion.cancel);
});

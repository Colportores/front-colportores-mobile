import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../agenda/presentation/providers/agenda_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../data/datasources/agendas_para_recordar_drift.dart';
import '../../data/repositories/marca_conciliacion_recordatorios_impl.dart';
import '../../domain/repositories/conciliacion_recordatorios_repository.dart';
import '../../domain/usecases/conciliar_recordatorios_use_case.dart';
import 'historial_notificaciones_providers.dart';
import 'preferencias_recordatorios_providers.dart';

// Cableado de «cada recordatorio local se guarda al dispararse» (HU-NOT-005, #416): al abrir la app y
// al volver a ella se guardan en el historial los recordatorios de visitas que ya sonaron.

/// Las agendas cuyo aviso ya tuvo que sonar. Sin DB abierta no hay agendas que leer: pedirlas lanza,
/// y la revisión lo deja en el log.
final agendasConAvisoVencidoProvider = Provider<AgendasConAvisoVencido>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return AgendasParaRecordarDrift(db);
});

/// Hasta dónde se revisaron los recordatorios que sonaron. En el equipo, `main.dart` lo sobreescribe
/// con el almacén seguro; por defecto (tests), en memoria.
final marcaConciliacionRecordatoriosProvider = Provider<MarcaConciliacionRecordatorios>(
  (ref) => MarcaConciliacionRecordatoriosEnMemoria(),
);

final conciliarRecordatoriosUseCaseProvider = Provider<ConciliarRecordatoriosUseCase>(
  (ref) => ConciliarRecordatoriosUseCase(
    ref.watch(agendasConAvisoVencidoProvider),
    ref.watch(preferenciasRecordatoriosRepositoryProvider),
    ref.watch(marcaConciliacionRecordatoriosProvider),
    ref.watch(registrarNotificacionUseCaseProvider),
    ahora: ref.watch(relojVisitaProvider),
  ),
);

/// Pide revisiones de a una: si llega un pedido mientras otra corre, se hace otra al terminar (puede
/// haber avisos más nuevos) y no dos a la vez.
final class ConciliadorSerie {
  ConciliadorSerie(this._revisar);

  final Future<void> Function() _revisar;
  bool _corriendo = false;
  bool _otraVez = false;

  Future<void> pedir() async {
    if (_corriendo) {
      _otraVez = true;
      return;
    }
    _corriendo = true;
    try {
      do {
        _otraVez = false;
        await _revisar();
      } while (_otraVez);
    } finally {
      _corriendo = false;
    }
  }
}

/// Quien pide las revisiones de los recordatorios que sonaron, o `null` sin sesión o sin DB abierta
/// (no hay agendas que mirar). Es de una sola serie para toda la app: el ingreso, el regreso a la app
/// y la apertura del centro de notificaciones comparten la misma cola.
final conciliadorRecordatoriosProvider = Provider<ConciliadorSerie?>((ref) {
  if (ref.watch(dbLocalProvider) == null) return null;
  final colportorId = ref.watch(sesionProvider.select((s) => s.value?.usuarioId));
  if (colportorId == null) return null;
  return ConciliadorSerie(() async {
    if (!ref.mounted) return;
    try {
      await ref.read(conciliarRecordatoriosUseCaseProvider).call(colportorId);
    } on Object catch (e) {
      // El caso de uso no lanza; si el cableado lo hace, la app sigue.
      AppLogger.instance.error(
        LogModulo.push,
        'RECORDATORIOS_CONCILIAR',
        'no se pudo revisar los recordatorios que sonaron',
        {'error': e.runtimeType.toString()},
      );
    }
  });
});

/// Guarda en el historial los recordatorios que sonaron, al abrir la app y cada vez que se vuelve a
/// ella (HU-NOT-005); el centro de notificaciones lo pide también al abrirse. Lo mira la pantalla
/// principal (`_Principal`, en `app.dart`): sin sesión ni DB abierta no hay agendas, y apenas se abre
/// la DB se revisa.
final conciliacionRecordatoriosProvider = Provider.autoDispose<void>((ref) {
  final conciliador = ref.watch(conciliadorRecordatoriosProvider);
  if (conciliador == null) return;
  final ciclo = AppLifecycleListener(onResume: () => unawaited(conciliador.pedir()));
  ref.onDispose(ciclo.dispose);
  unawaited(conciliador.pedir());
});

/// Antes de cambiar las preferencias de los recordatorios (HU-NOT-004): guarda lo que sonó con las de
/// antes, para que el historial no cuente con la anticipación nueva avisos que sonaron con la vieja.
/// Nunca lanza.
final conciliarAntesDeCambiarPreferenciasProvider = Provider<Future<void> Function(String)>(
  (ref) => (colportorId) async {
    try {
      await ref.read(conciliarRecordatoriosUseCaseProvider).call(colportorId);
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.push,
        'RECORDATORIOS_CONCILIAR_ANTES',
        'no se pudieron guardar los recordatorios que sonaron antes de cambiar las preferencias',
        {'error': e.runtimeType.toString()},
      );
    }
  },
);

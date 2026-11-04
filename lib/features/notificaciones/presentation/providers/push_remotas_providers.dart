import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/notificaciones/notificaciones_providers.dart';
import '../../../../core/notificaciones/push_remotas.dart';
import '../../data/repositories/auditoria_push_repository_drift.dart';
import '../../data/repositories/datos_locales_de_push_repository_drift.dart';
import '../../domain/entities/notificacion.dart';
import '../../domain/repositories/auditoria_push_repository.dart';
import '../../domain/repositories/datos_locales_de_push_repository.dart';
import '../../domain/usecases/recibir_push_remota_use_case.dart';
import 'historial_notificaciones_providers.dart';

// Cableado de las push remotas (HU-NOT-003). Presentation conoce domain; data se inyecta acá.

/// La auditoría local de las push. Sin DB abierta no hay dónde escribir: lanza.
final auditoriaPushRepositoryProvider = Provider<AuditoriaPushRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return AuditoriaPushRepositoryDrift(db);
});

/// Lo que la base local sabe para armar el texto de una push. Sin DB abierta lanza.
final datosLocalesDePushRepositoryProvider = Provider<DatosLocalesDePushRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return DatosLocalesDePushRepositoryDrift(db);
});

final recibirPushRemotaUseCaseProvider = Provider<RecibirPushRemotaUseCase>(
  (ref) => RecibirPushRemotaUseCase(
    ref.watch(registrarNotificacionUseCaseProvider),
    ref.watch(auditoriaPushRepositoryProvider),
    ref.watch(datosLocalesDePushRepositoryProvider),
    ahora: ref.watch(relojHistorialNotificacionesProvider),
  ),
);

/// El camino de los avisos que hay que mostrar con la app al frente (24C·08): `escuchaPushRemotas`
/// los deja acá y el aviso sutil de arriba (`AvisoPushEnAppHost`) los dibuja.
final class CanalAvisosPush {
  final _avisos = StreamController<Notificacion>.broadcast();

  Stream<Notificacion> get avisos => _avisos.stream;

  void mostrar(Notificacion aviso) {
    if (!_avisos.isClosed) _avisos.add(aviso);
  }

  void cerrar() => unawaited(_avisos.close());
}

final canalAvisosPushProvider = Provider<CanalAvisosPush>((ref) {
  final canal = CanalAvisosPush();
  ref.onDispose(canal.cerrar);
  return canal;
});

/// Abre el aviso de una push: lo marca como leído y lleva a su destino, si lo tiene (R-NO05). **Sin
/// efecto por defecto**; `main.dart` lo reemplaza con `EnganchesPushRemotas.enganches`, que conoce el
/// navegador raíz.
final abridorAvisoPushProvider = Provider<Future<void> Function(Notificacion aviso)>(
  (ref) => (aviso) async {},
);

/// Escucha las push remotas mientras haya sesión con la base abierta (`_Principal`, en `app.dart`,
/// la monta recién cuando la base está lista).
///
/// - Con la app al frente: la guarda en el historial y, si es nueva, la deja en [canalAvisosPushProvider]
///   para el aviso sutil (24C·08).
/// - Con un toque sobre la notificación del sistema (app en segundo plano o cerrada): la guarda si
///   no estaba y abre el aviso.
///
/// Los mensajes se atienden **de a uno y en el orden en que llegan**: dos push seguidas no se pisan
/// ni se pierde ninguna, y la que llegó última queda arriba. Nada de lo que llegue de afuera tira
/// esto abajo: cada mensaje que falla queda en el log (sin su contenido) y sigue el siguiente.
final escuchaPushRemotasProvider = Provider.autoDispose<void>((ref) {
  final push = ref.watch(pushRemotasProvider);
  final canal = ref.watch(canalAvisosPushProvider);
  var cola = Future<void>.value();

  Future<void> abrir(Notificacion aviso) async {
    try {
      await ref.read(abridorAvisoPushProvider)(aviso);
    } on Object catch (e) {
      AppLogger.instance.warn(LogModulo.push, 'PUSH_ABRIR_FAIL', 'no se pudo abrir el aviso', {
        'tipo': e.runtimeType.toString(),
      });
    }
  }

  Future<void> atender(MensajePush mensaje, {required bool tocada}) async {
    if (!ref.mounted) return;
    try {
      // Se arma al llegar el mensaje, no al escuchar: `_Principal` monta esto con la base ya abierta,
      // y si después se reemplaza (una recuperación), el caso de uso se rearma con la nueva.
      final recibida = await ref.read(recibirPushRemotaUseCaseProvider)(mensaje);
      if (!ref.mounted) return;
      switch (recibida.fold<ResultadoPush?>((_) => null, (r) => r)) {
        case null:
          AppLogger.instance.warn(
            LogModulo.push,
            'PUSH_GUARDAR_FAIL',
            'no se pudo guardar el aviso',
          );
        case PushNueva(:final aviso):
          if (tocada) {
            await abrir(aviso);
          } else {
            canal.mostrar(aviso);
          }
        case PushYaRecibida(:final aviso):
          if (tocada) await abrir(aviso);
        case PushDescartada():
          break;
      }
    } on Object catch (e) {
      AppLogger.instance.warn(LogModulo.push, 'PUSH_ATENDER_FAIL', 'no se pudo atender la push', {
        'tipo': e.runtimeType.toString(),
      });
    }
  }

  void encolar(MensajePush mensaje, {required bool tocada}) {
    cola = cola.then((_) => atender(mensaje, tocada: tocada));
  }

  final alFrente = push.conLaAppAbierta.listen((m) => encolar(m, tocada: false));
  final tocadas = push.tocadas.listen((m) => encolar(m, tocada: true));
  ref.onDispose(() {
    unawaited(alFrente.cancel());
    unawaited(tocadas.cancel());
  });
  unawaited(
    push.tomarLaQueAbrioLaApp().then<void>(
      (m) {
        if (m != null) encolar(m, tocada: true);
      },
      onError: (Object e) => AppLogger.instance.warn(
        LogModulo.push,
        'PUSH_INICIAL_FAIL',
        'no se pudo leer la push que abrió la app',
        {'tipo': e.runtimeType.toString()},
      ),
    ),
  );
});

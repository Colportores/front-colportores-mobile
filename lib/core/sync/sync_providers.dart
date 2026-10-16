import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../catalogo.dart';
import '../../datos/drift_job_store.dart';
import '../../datos/drift_local_store.dart';
import '../../datos/encolador_sync_motor.dart';
import '../../features/mapa/data/services/fuentes_sin_adaptador_ubicaciones.dart';
import '../../plataforma/conectividad_del_motor.dart';
import '../../plataforma/identidad_instalacion.dart';
import '../conectividad/conectividad_providers.dart';
import '../config/config_supabase.dart';
import '../database/database_providers.dart';
import '../logging/app_logger.dart';
import 'encolador_sync.dart';

// Cableado del motor de sync (contrato-sync-engine §3, #178). El motor es de Bruno (ADR-017,
// `packages/sync_engine`, `lib/datos/`, `lib/plataforma/`); esto lo arma con lo que la app ya tiene:
// la DB local abierta, la sesión de Supabase y el monitor de conectividad.

/// El sobre de esta instalación (§5.3). Leerlo del almacén seguro es asincrónico y el transporte
/// lo necesita sincrónico, así que `main.dart` lo carga antes de `runApp` y lo sobreescribe. El
/// valor por defecto es el de los tests y la demo sin backend: nunca sale del teléfono.
final sobreSyncProvider = Provider<ClientEnvelope>(
  (ref) => const ClientEnvelope(
    deviceId: '00000000-0000-7000-8000-000000000000',
    appVersion: versionApp,
  ),
);

/// El camino batch (§6): directo a `public.sync_push` y `public.sync_pull` (ADR-013). Sin Supabase
/// configurado (tests, demo), [TransporteSinBackend]: todo queda `PENDING`, nada se pierde.
///
/// El token es el JWT de la sesión vigente. El refresh es de `supabase_flutter` (§10): si el token
/// venció, el servidor contesta `401`, el lote queda `PENDING` y sube al próximo trigger.
final transporteSyncProvider = Provider<SyncTransport>((ref) {
  if (!ConfigSupabase.configurada) return const TransporteSinBackend();
  return SupabaseRpcTransport(
    projectUrl: Uri.parse(ConfigSupabase.url),
    anonKey: ConfigSupabase.anonKey,
    token: () async => Supabase.instance.client.auth.currentSession?.accessToken,
    device: ref.watch(sobreSyncProvider),
  );
});

/// El motor, mientras la DB local está abierta (`dbLocalProvider`); `null` sin DB.
///
/// La cola vive en esa DB, así que el motor se arma con ella y se tira cuando se cierra (cerrar
/// sesión, HU-AUTH-010): un motor con la DB cerrada no tiene dónde encolar.
final motorSyncProvider = Provider<SyncEngine?>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return null;
  final motor = SyncEngine(
    specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
    transport: ref.watch(transporteSyncProvider),
    jobs: DriftJobStore(db),
    store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
    connectivity: ConectividadDelMotor(ref.watch(monitorConectividadProvider)),
  );
  ref.onDispose(() => unawaited(motor.dispose()));
  return motor;
});

/// Por donde la capa `data` encola lo que escribe (contrato §3). Sin DB abierta no hay motor:
/// [EncoladorSyncSinMotor] falla a propósito y la escritura se revierte, en vez de quedar en el
/// teléfono sin subir nunca.
final encoladorSyncProvider = Provider<EncoladorSync>((ref) {
  final motor = ref.watch(motorSyncProvider);
  return motor == null ? const EncoladorSyncSinMotor() : EncoladorSyncMotor(motor);
});

/// Los triggers de §5.2 que vienen del sistema: la app vuelve al frente (sube lo pendiente y baja
/// el delta) o se va al fondo (sale ya lo crítico que esperaba su ventana de 2 s). Al armarse,
/// además, arranca un ciclo: lo que quedó en la cola de la sesión anterior sube sin esperar.
///
/// Lo observa la pantalla principal mientras la DB está abierta. Necesita el binding de Flutter
/// (`AppLifecycleListener`), por eso no vive dentro de [motorSyncProvider].
final cicloDeVidaSyncProvider = Provider<void>((ref) {
  final motor = ref.watch(motorSyncProvider);
  if (motor == null) return;
  final ciclo = AppLifecycleListener(
    onResume: () => _disparar(motor, SyncTrigger.appResumed),
    onHide: () => unawaited(_vaciar(motor)),
  );
  ref.onDispose(ciclo.dispose);
  _disparar(motor, SyncTrigger.appResumed);
});

void _disparar(SyncEngine motor, SyncTrigger trigger) {
  unawaited(
    motor.trigger(trigger).then<void>(
      (resultado) {
        if (resultado.failure case final falla?) {
          AppLogger.instance.warn(LogModulo.sync, 'CICLO_CORTADO', 'el ciclo quedó para después', {
            'trigger': trigger.name,
            'kind': falla.kind.name,
            'code': falla.code,
            'status': falla.status,
          });
        }
      },
      onError: (Object e, StackTrace st) => AppLogger.instance.error(
        LogModulo.sync,
        'CICLO_FAIL',
        'el ciclo de sync falló',
        {'trigger': trigger.name},
        e,
        st,
      ),
    ),
  );
}

Future<void> _vaciar(SyncEngine motor) async {
  try {
    await motor.flush();
  } on Object catch (e, st) {
    AppLogger.instance.error(
      LogModulo.sync,
      'FLUSH_FAIL',
      'no se pudo vaciar la cola',
      const {},
      e,
      st,
    );
  }
}

/// [SyncTransport] para cuando la app corre sin Supabase (tests, CI sin variables, demo): toda
/// llamada es una falla transitoria. Los jobs quedan `PENDING` en la cola, como sin señal, y
/// suben el día que la app arranque con backend.
final class TransporteSinBackend implements SyncTransport {
  const TransporteSinBackend();

  static const _falla = TransportFailure(
    FailureKind.transient,
    code: 'SIN_BACKEND',
    message: 'la app corre sin Supabase configurado',
  );

  @override
  Future<PushResult> push(PushBatch batch) async => throw _falla;

  @override
  Future<PullDelta> pull({required List<String> entities, String? watermark, int? limit}) async =>
      throw _falla;
}

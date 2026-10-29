import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../data/datasources/auditoria_backup_local.dart';
import '../../data/services/nivel_bateria_canal.dart';
import '../../data/services/revision_del_respaldo.dart';
import '../../data/services/servicio_respaldo_motor.dart';
import '../../domain/entities/estado_respaldo_drive.dart';
import '../../domain/repositories/respaldo_drive_repository.dart';
import '../../domain/services/nivel_bateria.dart';
import '../../domain/services/servicio_respaldo.dart';
import 'respaldo_drive_providers.dart';

/// La batería del teléfono (R-SY10). Por defecto, sin dato: nunca frena el respaldo. `main.dart` lo
/// reemplaza por el canal nativo ([NivelBateriaCanal]).
final nivelBateriaProvider = Provider<NivelBateria>((ref) => const NivelBateriaDesconocido());

/// El registro de las verificaciones del backup en el `audit_log` local; `null` sin DB abierta.
final auditoriaBackupProvider = Provider<AuditoriaBackupLocal?>((ref) {
  final db = ref.watch(dbLocalProvider);
  return db == null ? null : AuditoriaBackupLocal(db);
});

/// El respaldo en Drive (HU-SYNC-005, HU-SYNC-009), mientras haya DB abierta: sin ella, todo
/// pedido vuelve «sin motor».
///
/// Se arma con el estado de Drive **leído del almacén**, no del notifier: al terminar de conectar,
/// el notifier todavía no cambió su estado y el primer respaldo se tomaría por «sin Drive».
final servicioRespaldoProvider = Provider<ServicioRespaldo>((ref) {
  final motor = ref.watch(motorSyncProvider);
  final repo = ref.watch(respaldoDriveRepositoryProvider);
  final monitor = ref.watch(monitorConectividadProvider);
  final bateria = ref.watch(nivelBateriaProvider);
  final auditoria = ref.watch(auditoriaBackupProvider);

  EstadoRespaldoDriveNotifier estadoDrive() => ref.read(estadoRespaldoDriveProvider.notifier);

  return ServicioRespaldoMotor(
    backup: () => motor?.backup,
    estadoDrive: () async {
      final usuarioId = ref.read(sesionProvider).value?.usuarioId;
      if (usuarioId == null) return const DriveSinConectar();
      final estado = await repo.estado(usuarioId);
      return estado.fold((falla) => throw falla, (e) => e);
    },
    conexion: monitor.actual,
    bateria: bateria,
    alPermisoRevocado: () => estadoDrive().permisoRevocado(),
    alSinEspacio: () => estadoDrive().sinEspacio(),
    alGuardado: () => estadoDrive().respaldoGuardado(),
    alVerificar: (informe) async => auditoria?.registrar(
      cuando: informe.checkedAt,
      hayProblema: informe.needsRebase,
      problemas: informe.hasBackup ? informe.problems : const {'sin_respaldos'},
    ),
  );
});

/// El primer respaldo, justo después de conectar Drive (HU-SYNC-004, 16D·04): lo pidió la persona,
/// así que no espera Wi-Fi ni batería. Se usa en `main.dart` al armar el repositorio.
final class PrimerRespaldoConServicio implements PrimerRespaldoDrive {
  const PrimerRespaldoConServicio(this._servicio);

  /// Se pide al hacer el respaldo y no al armarse: el repositorio se arma antes que el motor.
  final ServicioRespaldo Function() _servicio;

  @override
  Future<bool> hacer() async {
    final resultado = await _servicio().respaldar(OrigenRespaldo.pedidoPorLaPersona);
    return resultado is RespaldoHecho;
  }
}

/// Lo que la app revisa al arrancar y al volver al frente (HU-SYNC-005, HU-SYNC-009): un respaldo
/// si lleva más de 24 horas sin uno y la verificación semanal de la cadena. Lo observa la pantalla
/// principal mientras la DB está abierta, junto a [cicloDeVidaSyncProvider].
final respaldoAlVolverProvider = Provider<void>((ref) {
  final motor = ref.watch(motorSyncProvider);
  if (motor == null) return;
  final revision = RevisionDelRespaldo(
    servicio: ref.watch(servicioRespaldoProvider),
    ultimoRespaldo: () async => (await motor.statusNow()).lastBackupAt,
    ultimaVerificacion: () async => ref.read(auditoriaBackupProvider)?.ultimaVerificacion(),
  );
  final ciclo = AppLifecycleListener(onResume: () => unawaited(revision.revisar()));
  ref.onDispose(ciclo.dispose);
  unawaited(revision.revisar());
});

/// Cuántos días lleva la persona sin un respaldo exitoso, si corresponde avisarle (HU-SYNC-005,
/// «Aviso por > 7 días sin backup»): solo con Drive conectado y un respaldo anterior. `null` si no
/// hay nada que avisar.
///
/// Sin un respaldo anterior no hay desde cuándo contar —no se guarda cuándo se conectó Drive—, así
/// que ese caso no avisa (queda como pendiente de decisión).
int? diasSinRespaldo({required DateTime? ultimo, required DateTime ahora}) {
  if (ultimo == null) return null;
  final pasado = ahora.difference(ultimo);
  if (pasado <= const Duration(days: 7)) return null;
  return pasado.inDays;
}

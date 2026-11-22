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
import '../../domain/services/programador_respaldo_nocturno.dart';
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
    alGuardado: () async {
      await estadoDrive().respaldoGuardado();
      // La clave envuelta viaja con el respaldo (ADR-006): sin ella, el respaldo no se abre en otro
      // teléfono. No espera: nunca lanza y un fallo se reintenta con el próximo respaldo.
      unawaited(ref.read(envoltorioEnDriveProvider).sincronizar());
    },
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
/// «Aviso por > 7 días sin backup»): solo con Drive conectado. `null` si no hay nada que avisar.
///
/// Se cuenta desde el último respaldo; **sin ninguno**, desde que se conectó Drive
/// ([conectadaDesde], #583): quien conectó hace 10 días y nunca tuvo un respaldo también lleva 10
/// días sin uno. Es el mismo aviso, con el mismo umbral y la misma cuenta. Sin ninguna de las dos
/// fechas no hay desde cuándo contar y no se avisa.
///
/// El número es de días contados hacia arriba: el día en curso cuenta.
int? diasSinRespaldo({
  required DateTime? ultimo,
  required DateTime ahora,
  DateTime? conectadaDesde,
}) {
  final desde = ultimo ?? conectadaDesde;
  if (desde == null) return null;
  final pasado = ahora.difference(desde);
  if (pasado <= const Duration(days: 7)) return null;
  // El día en curso cuenta (decisión del 29/10, QA #185): 7 días y 3 horas es «8 días», como el
  // ejemplo de la HU. El umbral sigue siendo «más de 7 días».
  final completos = pasado.inDays;
  return pasado == Duration(days: completos) ? completos : completos + 1;
}

/// El respaldo de la noche con la app cerrada (HU-SYNC-005, #583). `main.dart` lo reemplaza por el
/// planificador del sistema (`workmanager`); sin él (tests, escritorio) no programa nada.
final programadorDeRespaldoNocturnoProvider = Provider<ProgramadorDeRespaldoNocturno>(
  (ref) => const ProgramadorSinSegundoPlano(),
);

/// Mantiene programado el respaldo de la noche mientras haya Drive conectado: lo programa al
/// conectar (y en cada arranque, por si el sistema lo perdió: actualizar la app o forzar la
/// detención lo borra) y lo saca al desconectar o perder el permiso, para no despertar al teléfono
/// sin nada que subir. Lo observa la pantalla principal junto a [respaldoAlVolverProvider].
final respaldoNocturnoProgramadoProvider = Provider<void>((ref) {
  final programador = ref.watch(programadorDeRespaldoNocturnoProvider);
  ref.listen(estadoRespaldoDriveProvider, (_, estado) {
    switch (estado.value) {
      case DriveConectada() || DriveSinEspacio():
        unawaited(programador.programar());
      case DriveSinConectar() || DrivePermisoRevocado():
        unawaited(programador.cancelar());
      case null:
        // Todavía leyendo (o no se pudo leer): no se cambia lo que haya.
        break;
    }
  }, fireImmediately: true);
});

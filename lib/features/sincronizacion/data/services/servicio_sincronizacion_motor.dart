import 'package:sync_engine/sync_engine.dart';

import '../../domain/entities/estado_sincronizacion.dart';
import '../../domain/services/servicio_sincronizacion.dart';

/// [ServicioSincronizacion] sobre el motor de sync (`SyncEngine`, contrato §3): traduce su estado y
/// sus operaciones rechazadas a lo que muestra la vista 25, y no deja que sus tipos lleguen a la
/// pantalla.
final class ServicioSincronizacionMotor implements ServicioSincronizacion {
  const ServicioSincronizacionMotor(this._motor);

  final SyncEngine _motor;

  @override
  Future<EstadoSincronizacion> estado() async => _traducir(await _motor.statusNow());

  @override
  Stream<EstadoSincronizacion> get cambios => _motor.status.map(_traducir);

  static EstadoSincronizacion _traducir(SyncStatus s) => EstadoSincronizacion(
    pendientes: s.pending + s.inFlight + s.blocked + s.waiting,
    invalidas: s.invalid,
    conflictos: s.blocked + s.waiting,
    ultimoEnvio: s.lastPushAt,
    ultimaActualizacion: s.lastPullAt,
    ultimoRespaldo: s.lastBackupAt,
    actualizacionEnEspera: s.pullPausedReason != null,
    sesionSinRenovar: s.unauthorizedSince != null,
  );

  @override
  Future<ResultadoActualizacion> actualizarAhora() async {
    final SyncOutcome salida;
    try {
      salida = await _motor.syncNow();
    } on TransportFailure catch (falla) {
      return ActualizacionFallida(_motivo(falla));
    }
    if (salida.skipped) {
      // El motor se apagó (se cerró la sesión) mientras se esperaba: no hubo ciclo.
      return const ActualizacionFallida(MotivoFallaActualizacion.servidor);
    }
    if (salida.failure case final falla?) {
      return ActualizacionFallida(_motivo(falla), enviadas: salida.pushed);
    }
    // Las que esperan un conflicto siguen ahí aunque este ciclo no haya encontrado ninguna nueva.
    final esperando = await _motor.statusNow();
    final enEspera = esperando.blocked + esperando.waiting;
    return ActualizacionCompleta(
      enviadas: salida.pushed,
      recibidas: salida.pulled,
      rechazadas: salida.invalidated,
      conflictos: enEspera > salida.conflicts ? enEspera : salida.conflicts,
    );
  }

  /// Un `401` es una sesión que no se renueva: reintentar no lo arregla, hay que volver a entrar.
  static MotivoFallaActualizacion _motivo(TransportFailure falla) =>
      falla.status == 401 ? MotivoFallaActualizacion.sesion : MotivoFallaActualizacion.servidor;

  @override
  Future<List<OperacionFallida>> operacionesFallidas() async {
    final fallidas = await _motor.failedOperations();
    return [
      for (final f in fallidas)
        OperacionFallida(
          id: f.jobId,
          tabla: f.entity,
          tipo: switch (f.op) {
            Op.insert => TipoOperacion.alta,
            Op.update => TipoOperacion.cambio,
            Op.delete => TipoOperacion.baja,
          },
          fecha: f.createdAt,
          codigo: f.code,
          error: f.lastError,
        ),
    ];
  }

  @override
  Future<int> reintentarFallidas({String? id}) async {
    if (id == null) return _motor.requeueAllInvalid();
    await _motor.requeue(id);
    return 1;
  }

  @override
  void aplicarModoAhorro({required bool activo}) => _motor.setDataSaver(activo);
}

/// [ServicioSincronizacion] mientras no hay motor (la DB local está cerrada): no hay cola que
/// mostrar. La pantalla lo toma como «no pudimos revisar» y ofrece «Reintentar».
final class ServicioSincronizacionSinMotor implements ServicioSincronizacion {
  const ServicioSincronizacionSinMotor();

  static final _falla = StateError('el motor de sync no está disponible: la DB local está cerrada');

  @override
  Future<EstadoSincronizacion> estado() => Future<EstadoSincronizacion>.error(_falla);

  @override
  Stream<EstadoSincronizacion> get cambios => const Stream<EstadoSincronizacion>.empty();

  @override
  Future<ResultadoActualizacion> actualizarAhora() async =>
      const ActualizacionFallida(MotivoFallaActualizacion.servidor);

  @override
  Future<List<OperacionFallida>> operacionesFallidas() async => const [];

  @override
  Future<int> reintentarFallidas({String? id}) async => 0;

  @override
  void aplicarModoAhorro({required bool activo}) {}
}

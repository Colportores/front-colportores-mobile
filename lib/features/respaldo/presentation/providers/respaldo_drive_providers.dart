import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../data/repositories/respaldo_drive_repository_impl.dart';
import '../../data/services/servicio_google.dart';
import '../../domain/entities/estado_respaldo_drive.dart';
import '../../domain/repositories/respaldo_drive_repository.dart';

/// El respaldo en Drive (HU-SYNC-004). Por defecto —tests y demo sin registrar la app en Google—
/// corre sobre un almacén en memoria y un Google sin configurar, donde nadie puede conectar;
/// `main.dart` lo reemplaza por el Keystore y `google_sign_in`.
final respaldoDriveRepositoryProvider = Provider<RespaldoDriveRepository>(
  (ref) =>
      RespaldoDriveRepositoryImpl(AlmacenSeguroEnMemoria(), const ServicioGoogleSinConfigurar()),
);

/// El token de acceso de Drive del usuario con la sesión iniciada, pedido en silencio a Google; es
/// lo que recibe `DriveArchive.token` cuando el motor de backup (HU-SYNC-005, #185) se arme.
/// `null` sin sesión, sin Drive conectado o si Google ya no da el permiso.
final tokenDriveProvider = Provider<Future<String?> Function()>((ref) {
  final repo = ref.watch(respaldoDriveRepositoryProvider);
  return () async {
    final usuarioId = ref.read(sesionProvider).value?.usuarioId;
    return usuarioId == null ? null : repo.tokenDeAcceso(usuarioId);
  };
});

/// Cómo terminó un intento de conectar.
sealed class ResultadoConexionDrive {
  const ResultadoConexionDrive();
}

/// Quedó conectado. [primerRespaldoHecho] dice qué se le avisa a la persona.
final class DriveQuedoConectado extends ResultadoConexionDrive {
  const DriveQuedoConectado({required this.primerRespaldoHecho});

  final bool primerRespaldoHecho;
}

/// No quedó conectado, con la causa para que la hoja diga qué hacer.
final class DriveNoQuedoConectado extends ResultadoConexionDrive {
  const DriveNoQuedoConectado(this.falla);

  final Failure falla;
}

/// Ya había una conexión o una desconexión en curso: no se hizo nada.
final class DriveOcupado implements ResultadoConexionDrive, ResultadoDesconexionDrive {
  const DriveOcupado();
}

/// Cómo terminó un intento de desconectar.
sealed class ResultadoDesconexionDrive {
  const ResultadoDesconexionDrive();
}

/// Quedó desconectado.
final class DriveQuedoDesconectado extends ResultadoDesconexionDrive {
  const DriveQuedoDesconectado();
}

/// No se pudo olvidar la cuenta: sigue conectado.
final class DriveNoQuedoDesconectado extends ResultadoDesconexionDrive {
  const DriveNoQuedoDesconectado(this.falla);

  final Failure falla;
}

/// Riverpod 3 reintenta solo un provider que falla, con esperas crecientes: la fila se quedaría en
/// «Revisando…» en vez de mostrar el error con su «Reintentar».
Duration? _sinReintentos(int intento, Object error) => null;

/// El estado del respaldo en Drive del usuario con la sesión iniciada. Sin sesión, «sin conectar».
/// Cambia de usuario junto con la sesión: el Drive de uno no es el del otro.
final estadoRespaldoDriveProvider =
    AsyncNotifierProvider<EstadoRespaldoDriveNotifier, EstadoRespaldoDrive>(
      EstadoRespaldoDriveNotifier.new,
      retry: _sinReintentos,
    );

class EstadoRespaldoDriveNotifier extends AsyncNotifier<EstadoRespaldoDrive> {
  /// Hay una conexión o una desconexión en curso. Es un campo y no solo el estado: la guarda tiene
  /// que cortar el segundo toque aunque llegue antes de que se vuelva a dibujar.
  bool _enCurso = false;

  String? _usuarioId;

  RespaldoDriveRepository get _repo => ref.read(respaldoDriveRepositoryProvider);

  @override
  Future<EstadoRespaldoDrive> build() {
    _usuarioId = ref.watch(sesionProvider.select((s) => s.value?.usuarioId));
    ref.watch(respaldoDriveRepositoryProvider);
    return _leer();
  }

  /// Lee el estado guardado. Si el almacén no se deja leer, lanza la falla: la fila no afirma «sin
  /// conectar» sobre algo que no pudo mirar.
  Future<EstadoRespaldoDrive> _leer() async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return const DriveSinConectar();
    final leido = await _repo.estado(usuarioId);
    final estado = leido.fold<EstadoRespaldoDrive>((falla) => throw falla, (e) => e);
    // Mira en segundo plano si Google todavía tiene el permiso: si la persona lo quitó desde su
    // cuenta, la fila lo dice al abrir Configuración y no recién cuando falle un respaldo.
    if (estado is DriveConectada || estado is DriveSinEspacio) {
      unawaited(_verificarPermiso(usuarioId));
    }
    return estado;
  }

  Future<void> _verificarPermiso(String usuarioId) async {
    final resultado = await ref.read(respaldoDriveRepositoryProvider).verificarPermiso(usuarioId);
    if (!ref.mounted || _usuarioId != usuarioId) return;
    resultado.fold((_) {}, (estado) {
      // Una conexión o desconexión en curso es más nueva que esta mirada.
      if (!_enCurso && state.value != estado) state = AsyncData(estado);
    });
  }

  /// Vuelve a leer el estado (el «Reintentar» de la fila cuando no se pudo leer).
  Future<void> recargar() async {
    state = const AsyncLoading<EstadoRespaldoDrive>();
    final nuevo = await AsyncValue.guard(_leer);
    if (ref.mounted) state = nuevo;
  }

  /// Conecta Drive: abre la pantalla de Google, y con el permiso queda guardado y se intenta el
  /// primer respaldo. Una sola conexión (o desconexión) a la vez: la segunda llamada devuelve
  /// [DriveOcupado]. Nunca lanza.
  Future<ResultadoConexionDrive> conectar() async {
    final usuarioId = _usuarioId;
    if (_enCurso || usuarioId == null) return const DriveOcupado();
    _enCurso = true;
    try {
      final resultado = await _repo.conectar(usuarioId);
      return resultado.fold(DriveNoQuedoConectado.new, (conexion) {
        if (ref.mounted && _usuarioId == usuarioId) state = AsyncData(conexion.estado);
        return DriveQuedoConectado(primerRespaldoHecho: conexion.primerRespaldoHecho);
      });
    } on Object {
      return const DriveNoQuedoConectado(FailureDriveNoConectado());
    } finally {
      _enCurso = false;
    }
  }

  /// Desconecta Drive: olvida la cuenta y le pide a Google que retire el permiso. Una sola conexión
  /// (o desconexión) a la vez: la segunda llamada devuelve [DriveOcupado]. Nunca lanza.
  Future<ResultadoDesconexionDrive> desconectar() async {
    final usuarioId = _usuarioId;
    if (_enCurso || usuarioId == null) return const DriveOcupado();
    _enCurso = true;
    try {
      final resultado = await _repo.desconectar(usuarioId);
      return resultado.fold(DriveNoQuedoDesconectado.new, (_) {
        if (ref.mounted && _usuarioId == usuarioId) state = const AsyncData(DriveSinConectar());
        return const DriveQuedoDesconectado();
      });
    } on Object {
      return const DriveNoQuedoDesconectado(FailureInesperado());
    } finally {
      _enCurso = false;
    }
  }

  /// El respaldo recibió `401` de Drive: pasa a «Reconectar» (HU-SYNC-004, escenario «Edge»). Lo
  /// llama el motor de backup.
  Future<void> permisoRevocado() => _aplicar((repo, u) => repo.marcarPermisoRevocado(u));

  /// Drive no tiene espacio: la fila lo dice (16D·10). Lo llama el motor de backup.
  Future<void> sinEspacio() => _aplicar((repo, u) => repo.marcarSinEspacio(u));

  /// Un respaldo se guardó: sale de «sin espacio». Lo llama el motor de backup.
  Future<void> respaldoGuardado() => _aplicar((repo, u) => repo.marcarRespaldoGuardado(u));

  Future<void> _aplicar(
    Future<dynamic> Function(RespaldoDriveRepository repo, String usuarioId) cambio,
  ) async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return;
    await cambio(_repo, usuarioId);
    if (!ref.mounted || _usuarioId != usuarioId || _enCurso) return;
    final nuevo = await _repo.estado(usuarioId);
    if (!ref.mounted) return;
    nuevo.fold((_) {}, (estado) => state = AsyncData(estado));
  }
}

/// Cuándo se hizo el último respaldo, según el motor de sync, y se actualiza cuando el motor hace
/// uno (`null` si todavía no hubo, o sin la DB abierta).
///
/// No depende de [estadoRespaldoDriveProvider]: si dependiera, al volver a Configuración desde otra
/// pantalla los dos se reconstruirían en cadena durante el `build` de la página y Riverpod lo
/// rechaza.
final ultimoRespaldoDriveProvider = StreamProvider.autoDispose<DateTime?>((ref) async* {
  final motor = ref.watch(motorSyncProvider);
  if (motor == null) {
    yield null;
    return;
  }
  yield (await motor.statusNow()).lastBackupAt;
  yield* motor.status.map((estado) => estado.lastBackupAt);
});

/// Se avisó «No conectamos tu Drive. Podés hacerlo cuando quieras.» (16D·07): la persona cerró la
/// pantalla de Google. El aviso se queda en Configuración hasta que vuelva a intentarlo o salga de
/// la pantalla.
final avisoDriveCanceladoProvider = NotifierProvider.autoDispose<AvisoDriveCancelado, bool>(
  AvisoDriveCancelado.new,
);

class AvisoDriveCancelado extends Notifier<bool> {
  @override
  bool build() => false;

  void mostrar() => state = true;

  void ocultar() => state = false;
}

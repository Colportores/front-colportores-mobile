import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
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

/// Se conectó, pero con **otra** cuenta de Google que la del respaldo anterior (16E·01): el respaldo
/// queda frenado hasta que la persona elija con cuál seguir. [estado] trae las dos cuentas.
final class DriveQuedoEnOtraCuenta extends ResultadoConexionDrive {
  const DriveQuedoEnOtraCuenta(this.estado);

  final DriveCuentaPorConfirmar estado;
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

  /// Sube con cada conexión o desconexión. Una lectura lenta del permiso que empezó antes de un
  /// cambio así vio un estado que ya no existe: su resultado se descarta.
  int _generacion = 0;

  String? _usuarioId;

  RespaldoDriveRepository get _repo => ref.read(respaldoDriveRepositoryProvider);

  @override
  Future<EstadoRespaldoDrive> build() {
    _usuarioId = ref.watch(sesionProvider.select((s) => s.value?.usuarioId));
    ref.watch(respaldoDriveRepositoryProvider);
    // Un cambio de estado borra el día en que se ocultó la franja de Hoy (16F·04): se vuelve a leer.
    // Es un aviso, no una dependencia: ver [franjaDriveOcultaProvider].
    listenSelf((anterior, nuevo) {
      if (anterior?.value != nuevo.value && nuevo.hasValue) {
        ref.invalidate(franjaDriveOcultaProvider);
      }
    });
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
    final generacion = _generacion;
    final resultado = await ref.read(respaldoDriveRepositoryProvider).verificarPermiso(usuarioId);
    if (!ref.mounted || _usuarioId != usuarioId || _generacion != generacion) return;
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
  ///
  /// Con [conPrimerRespaldo] en `false` no se hace el primer respaldo: es la conexión de «Recuperar
  /// mi respaldo» (16G·03, #707), que no sube el teléfono vacío.
  Future<ResultadoConexionDrive> conectar({bool conPrimerRespaldo = true}) async {
    final usuarioId = _usuarioId;
    if (_enCurso || usuarioId == null) return const DriveOcupado();
    _enCurso = true;
    _generacion++;
    try {
      final resultado = await _repo.conectar(usuarioId, conPrimerRespaldo: conPrimerRespaldo);
      return resultado.fold(DriveNoQuedoConectado.new, _alConectar(usuarioId));
    } on Object {
      return const DriveNoQuedoConectado(FailureDriveNoConectado());
    } finally {
      _enCurso = false;
      _generacion++;
    }
  }

  /// Lo que hace una conexión lograda: deja el estado nuevo y dice cómo quedó.
  ResultadoConexionDrive Function(ConexionDrive) _alConectar(String usuarioId) => (conexion) {
    if (ref.mounted && _usuarioId == usuarioId) state = AsyncData(conexion.estado);
    return switch (conexion.estado) {
      final DriveCuentaPorConfirmar otra => DriveQuedoEnOtraCuenta(otra),
      _ => DriveQuedoConectado(primerRespaldoHecho: conexion.primerRespaldoHecho),
    };
  };

  /// «Seguir con la cuenta nueva» (16E·01 y 16E·02): la cuenta por confirmar pasa a ser la del
  /// respaldo y se intenta el primer respaldo en ella. Una sola operación a la vez: la segunda
  /// llamada devuelve [DriveOcupado]. Nunca lanza.
  Future<ResultadoConexionDrive> confirmarCuentaNueva() async {
    final usuarioId = _usuarioId;
    if (_enCurso || usuarioId == null) return const DriveOcupado();
    _enCurso = true;
    _generacion++;
    try {
      final resultado = await _repo.confirmarCuentaNueva(usuarioId);
      return resultado.fold(DriveNoQuedoConectado.new, _alConectar(usuarioId));
    } on Object {
      return const DriveNoQuedoConectado(FailureDriveNoConectado());
    } finally {
      _enCurso = false;
      _generacion++;
    }
  }

  /// Desconecta Drive: olvida la cuenta y le pide a Google que retire el permiso. Una sola conexión
  /// (o desconexión) a la vez: la segunda llamada devuelve [DriveOcupado]. Nunca lanza.
  Future<ResultadoDesconexionDrive> desconectar() async {
    final usuarioId = _usuarioId;
    if (_enCurso || usuarioId == null) return const DriveOcupado();
    _enCurso = true;
    _generacion++;
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
      _generacion++;
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

/// Desde cuándo está conectado el Drive de la persona con la sesión iniciada (#583): de ahí se
/// cuentan los días «sin respaldo» cuando todavía no hubo ninguno. `null` sin sesión, sin cuenta o si
/// el almacén no se deja leer. Se vuelve a leer cuando Drive pasa a estar conectado.
final conectadaDesdeDriveProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  final usuarioId = ref.watch(sesionProvider.select((s) => s.value?.usuarioId));
  if (usuarioId == null) return null;
  ref.watch(estadoRespaldoDriveProvider.select((estado) => estado.value is DriveConectada));
  return ref.watch(respaldoDriveRepositoryProvider).conectadaDesde(usuarioId);
}, retry: _sinReintentos);

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

/// La hora de ahora, para saber si la franja del Drive de Hoy sigue oculta (es «hasta mañana»).
final relojRespaldoDriveProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// El día en que se ocultó la franja del Drive de Hoy (16F·04, a las 00:00 de la hora del teléfono), o
/// `null` si no está oculta.
///
/// Es un provider aparte y **nadie depende de él con otro provider**: lo miran los widgets de Hoy
/// directamente, junto con [estadoRespaldoDriveProvider] (una cadena de providers que se reconstruye
/// al volver a una pantalla durante su `build` la rechaza Riverpod; ver [conectadaDesdeDriveProvider]).
/// El estado del respaldo le avisa cuando cambia (conectar, perder el permiso, quedarse sin espacio,
/// guardar un respaldo): el repositorio ya borró el día y acá se vuelve a leer.
final franjaDriveOcultaProvider = AsyncNotifierProvider<FranjaDriveOcultaNotifier, DateTime?>(
  FranjaDriveOcultaNotifier.new,
  retry: _sinReintentos,
);

class FranjaDriveOcultaNotifier extends AsyncNotifier<DateTime?> {
  /// Hay un «Ocultar» en curso. Es un campo y no solo el estado: corta el segundo toque aunque llegue
  /// antes de que se vuelva a dibujar.
  bool _enCurso = false;

  @override
  Future<DateTime?> build() async {
    final usuarioId = ref.watch(sesionProvider.select((s) => s.value?.usuarioId));
    if (usuarioId == null) return null;
    return ref.watch(respaldoDriveRepositoryProvider).franjaOcultaEl(usuarioId);
  }

  /// Oculta la franja hasta mañana. Devuelve `true` si quedó anotado; con `false` la franja sigue a
  /// la vista (no se pudo anotar, o ya había un «Ocultar» en curso): nada queda trabado.
  Future<bool> ocultar() async {
    final usuarioId = ref.read(sesionProvider).value?.usuarioId;
    if (_enCurso || usuarioId == null) return false;
    _enCurso = true;
    try {
      final repo = ref.read(respaldoDriveRepositoryProvider);
      final anotado = (await repo.ocultarFranja(usuarioId)).isRight();
      if (!anotado) return false;
      final dia = await repo.franjaOcultaEl(usuarioId);
      if (ref.mounted) state = AsyncData(dia);
      return dia != null;
    } on Object {
      return false;
    } finally {
      _enCurso = false;
    }
  }
}

/// Qué le pasa al respaldo que Hoy tiene que avisar (16F·01 y 16F·02): se perdió el permiso o el
/// Drive está lleno.
enum ProblemaDeRespaldoEnHoy { permisoRevocado, sinEspacio }

/// El problema del respaldo que Hoy tiene que avisar, o `null` si no hay ninguno (conectado, sin
/// conectar, con otra cuenta por confirmar, o todavía leyendo).
ProblemaDeRespaldoEnHoy? problemaDeRespaldo(EstadoRespaldoDrive? estado) => switch (estado) {
  DrivePermisoRevocado() => ProblemaDeRespaldoEnHoy.permisoRevocado,
  DriveSinEspacio() => ProblemaDeRespaldoEnHoy.sinEspacio,
  _ => null,
};

/// Lo que Hoy dibuja del respaldo en Drive: la [franja] (16F·01 y 16F·02), o `null` si no hay problema
/// o la persona la ocultó por hoy; y la [marca] roja del engranaje, que sale justo cuando hay problema
/// y la franja está oculta (16F·04).
///
/// Mientras todavía se lee si estaba oculta no se dibuja ninguna de las dos: el problema aparece al
/// leer, sin parpadeo. Con el estado de otro día, la franja vuelve (es «hasta mañana»).
({ProblemaDeRespaldoEnHoy? franja, bool marca}) franjaDriveEnHoy({
  required EstadoRespaldoDrive? estado,
  required AsyncValue<DateTime?> oculta,
  required DateTime ahora,
}) {
  final problema = problemaDeRespaldo(estado);
  if (problema == null || !oculta.hasValue) return (franja: null, marca: false);
  final dia = oculta.value;
  final ocultaHoy = dia != null && dia == DateTime(ahora.year, ahora.month, ahora.day);
  return ocultaHoy ? (franja: null, marca: true) : (franja: problema, marca: false);
}

/// Lo mismo que [franjaDriveEnHoy], leído de los providers desde un widget de Hoy.
({ProblemaDeRespaldoEnHoy? franja, bool marca}) leerFranjaDriveEnHoy(WidgetRef ref) {
  // Al volver al frente se vuelve a mirar contra el día de ahora (16F·04).
  ref.watch(franjaDriveAlVolverProvider);
  return franjaDriveEnHoy(
    estado: ref.watch(estadoRespaldoDriveProvider.select((estado) => estado.value)),
    oculta: ref.watch(franjaDriveOcultaProvider),
    ahora: ref.read(relojRespaldoDriveProvider)(),
  );
}

/// Cuántas veces volvió la app al frente. Hoy lo mira para volver a leer si la franja oculta «hasta
/// mañana» ya es de otro día: quien la ocultó anoche y abre la app por la mañana la ve de nuevo sin
/// reiniciarla.
final franjaDriveAlVolverProvider = NotifierProvider<FranjaDriveAlVolver, int>(
  FranjaDriveAlVolver.new,
);

class FranjaDriveAlVolver extends Notifier<int> {
  @override
  int build() {
    final ciclo = AppLifecycleListener(onResume: () => state++);
    ref.onDispose(ciclo.dispose);
    return 0;
  }
}

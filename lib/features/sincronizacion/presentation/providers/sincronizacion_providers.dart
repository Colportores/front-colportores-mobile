import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../data/services/servicio_sincronizacion_motor.dart';
import '../../domain/entities/estado_sincronizacion.dart';
import '../../domain/services/servicio_sincronizacion.dart';

/// El motor de sync visto desde la pantalla de sincronización (vista 25). Sin motor (la DB local
/// está cerrada) la pantalla dice que no pudo revisar el estado.
final servicioSincronizacionProvider = Provider<ServicioSincronizacion>((ref) {
  final motor = ref.watch(motorSyncProvider);
  return motor == null
      ? const ServicioSincronizacionSinMotor()
      : ServicioSincronizacionMotor(motor);
});

/// La hora de ahora, para decir «hace 3 min». Los tests la fijan.
final ahoraSincronizacionProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Si el teléfono ya tiene respaldo configurado (Google Drive, HU-SYNC-004) o no. Hasta que llegue la
/// autorización de Drive (#184) y el respaldo (#185) no hay respaldo posible: la pantalla lo dice
/// («nunca») en vez de ocultarlo.
final respaldoConfiguradoProvider = Provider<bool>((ref) => false);

/// A dónde lleva «Conectar Google Drive» de la fila de respaldo (la fila «Cuenta Drive» de
/// Configuración, HU-SYNC-004). `null` mientras esa pantalla no exista: el aviso no ofrece un botón
/// que no lleva a ningún lado.
final conectarDriveProvider = Provider<VoidCallback?>((ref) => null);

/// Sin reintento automático: si no se puede leer el estado, la pantalla ofrece «Reintentar».
Duration? _sinReintentos(int intento, Object error) => null;

/// El estado de la sincronización mientras la pantalla lo mira: el de ahora y, después, cada cambio
/// que avisa el motor. Si el estado de ahora llega después de un cambio, no lo pisa (es más viejo).
final estadoSincronizacionProvider = StreamProvider.autoDispose<EstadoSincronizacion>((ref) {
  final servicio = ref.watch(servicioSincronizacionProvider);
  final salida = StreamController<EstadoSincronizacion>();
  StreamSubscription<EstadoSincronizacion>? escucha;
  var llegoUnCambio = false;
  salida
    ..onListen = () {
      escucha = servicio.cambios.listen((estado) {
        llegoUnCambio = true;
        if (!salida.isClosed) salida.add(estado);
      }, onError: (Object error, StackTrace rastro) => salida.addError(error, rastro));
      unawaited(
        servicio.estado().then<void>(
          (estado) {
            if (!llegoUnCambio && !salida.isClosed) salida.add(estado);
          },
          onError: (Object error, StackTrace rastro) {
            if (!salida.isClosed) salida.addError(error, rastro);
          },
        ),
      );
    }
    ..onCancel = () => escucha?.cancel();
  ref.onDispose(() => unawaited(salida.close()));
  return salida.stream;
}, retry: _sinReintentos);

/// Las operaciones que el servidor rechazó (HU-SYNC-007, «Ver detalle»). Se vuelven a pedir cuando
/// cambia cuántas hay.
final operacionesFallidasProvider = FutureProvider.autoDispose<List<OperacionFallida>>((ref) async {
  final cuantas = ref.watch(
    estadoSincronizacionProvider.select((estado) => estado.value?.invalidas ?? 0),
  );
  if (cuantas == 0) return const [];
  return ref.watch(servicioSincronizacionProvider).operacionesFallidas();
}, retry: _sinReintentos);

/// Dónde está «Actualizar ahora».
sealed class FaseActualizacion extends Equatable {
  const FaseActualizacion();

  @override
  List<Object?> get props => const [];
}

/// Nada en curso.
final class SinActualizar extends FaseActualizacion {
  const SinActualizar();
}

/// Enviando y trayendo cambios. [pendientesAlEmpezar] son las operaciones que había para subir
/// (para decir «Enviando 2 de 3»).
final class Actualizando extends FaseActualizacion {
  const Actualizando({this.pendientesAlEmpezar = 0});

  final int pendientesAlEmpezar;

  @override
  List<Object?> get props => [pendientesAlEmpezar];
}

/// Terminó bien. La pantalla lo avisa una vez (el aviso «Listo: …»).
final class Actualizado extends FaseActualizacion {
  const Actualizado(this.resultado, {required this.numero});

  final ActualizacionCompleta resultado;

  /// Cuántas actualizaciones van: dos iguales seguidas son dos avisos.
  final int numero;

  @override
  List<Object?> get props => [resultado, numero];
}

/// No se pudo. Lo pendiente sigue guardado en el teléfono.
final class NoSePudoActualizar extends FaseActualizacion {
  const NoSePudoActualizar(this.motivo, {required this.numero});

  final MotivoFallaActualizacion motivo;
  final int numero;

  @override
  List<Object?> get props => [motivo, numero];
}

/// «Actualizar ahora» en curso o recién terminado (HU-SYNC-007). Vive mientras la sesión: si se
/// sale de la pantalla en medio de una actualización y se vuelve a entrar, sigue diciendo
/// «Actualizando…» y no deja empezar otra encima.
final actualizacionProvider = NotifierProvider<ActualizacionNotifier, FaseActualizacion>(
  ActualizacionNotifier.new,
);

class ActualizacionNotifier extends Notifier<FaseActualizacion> {
  int _numero = 0;

  @override
  FaseActualizacion build() {
    // Otro motor (otro ingreso) es otra historia: lo que quedó de la sesión anterior no vale.
    ref.watch(servicioSincronizacionProvider);
    return const SinActualizar();
  }

  /// Sube lo pendiente y baja lo del coordinador. Con [reintentarFallidas] antes devuelve a la cola
  /// las operaciones rechazadas (todas, o solo la de [idFallida]). Un segundo pedido mientras hay
  /// uno en curso no hace nada.
  Future<void> actualizar({bool reintentarFallidas = false, String? idFallida}) async {
    if (state is Actualizando) return;
    final servicio = ref.read(servicioSincronizacionProvider);
    final pendientes = ref.read(estadoSincronizacionProvider).value?.pendientes ?? 0;
    final numero = ++_numero;
    state = Actualizando(pendientesAlEmpezar: pendientes);
    ResultadoActualizacion resultado;
    try {
      if (reintentarFallidas || idFallida != null) {
        await servicio.reintentarFallidas(id: idFallida);
      }
      resultado = await servicio.actualizarAhora();
    } on Object catch (e, st) {
      AppLogger.instance.error(
        LogModulo.sync,
        'ACTUALIZAR_AHORA',
        'falló la actualización manual',
        const {},
        e,
        st,
      );
      resultado = const ActualizacionFallida(MotivoFallaActualizacion.servidor);
    }
    // Otro motor tomó el lugar (cerró sesión): este resultado ya no es de nadie.
    if (!ref.mounted || ref.read(servicioSincronizacionProvider) != servicio) return;
    state = switch (resultado) {
      final ActualizacionCompleta ok => Actualizado(ok, numero: numero),
      ActualizacionFallida(:final motivo) => NoSePudoActualizar(motivo, numero: numero),
    };
  }

  /// Al abrir la pantalla: un fallo o un éxito viejos no se muestran como si fueran de ahora. Lo que
  /// está en curso sí sigue.
  void olvidarResultado() {
    if (state is Actualizado || state is NoSePudoActualizar) state = const SinActualizar();
  }
}

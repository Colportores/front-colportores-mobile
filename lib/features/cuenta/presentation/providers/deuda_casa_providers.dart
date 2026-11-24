import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../data/datasources/deuda_con_la_casa_local_data_source.dart';
import '../../data/repositories/deuda_con_la_casa_repository_impl.dart';
import '../../domain/entities/deuda_con_la_casa.dart';
import '../../domain/repositories/deuda_con_la_casa_repository.dart';
import 'cuenta_providers.dart';

// Cableado de la deuda con la casa editora (HU-CTA-002, vista 33B). Presentation conoce domain; data
// se inyecta acá.

/// El repositorio de la deuda: la cuenta se hace en el teléfono con lo que baja con la sincronización
/// (decisión de Cristian, 05/11; backend-supabase 0179, #254), sin llamar al servidor. La hora de la
/// cuenta sale del reloj de Mi Cuenta ([relojCuentaProvider]). Sin DB abierta no hay de dónde leer.
final deudaConLaCasaRepositoryProvider = Provider<DeudaConLaCasaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return const DeudaConLaCasaSinBase();
  return DeudaConLaCasaRepositoryImpl(
    DeudaConLaCasaLocalDrift(db),
    ahora: ref.watch(relojCuentaProvider),
  );
});

/// Por qué no hay una lectura de la deuda.
enum FalloDeLaDeuda {
  /// El teléfono todavía no sincronizó nunca: no sabe nada de la deuda y necesita conexión para
  /// bajarla. No es «no debés nada».
  sinConexion,

  /// No se pudo leer lo que bajó (la base local falló).
  noDisponible,
}

/// Lo que sabe la pantalla de la deuda con la casa editora: lo último que se calculó con lo que bajó
/// (con la hora de esa bajada) y si se está leyendo de nuevo o la última lectura falló.
final class EstadoDeLaDeuda extends Equatable {
  const EstadoDeLaDeuda({this.lectura, this.actualizando = false, this.fallo});

  /// La deuda calculada con lo último que bajó, con la hora de esa bajada. `null` = no hay.
  final LecturaDeLaDeuda? lectura;

  /// Se está leyendo.
  final bool actualizando;

  /// Por qué no hay lectura nueva; `null` si la hay (o si todavía se está leyendo).
  final FalloDeLaDeuda? fallo;

  @override
  List<Object?> get props => [lectura, actualizando, fallo];
}

/// La deuda del colportor [colportorId] con la casa editora.
///
/// Se calcula en el teléfono con lo que bajó con la sincronización: al abrirse la lee enseguida y se
/// vuelve a leer sola cada vez que la sincronización trae algo que la cambia. Si lo que bajó no se puede
/// leer, el error queda a la vista con su «Reintentar»; si todavía no se sincronizó nunca, dice que hace
/// falta conexión. Es compartido por la tarjeta de Mi Cuenta y por la pantalla 33B: leerla dos veces a la
/// vez cuenta como una.
final deudaConLaCasaProvider = NotifierProvider.autoDispose
    .family<DeudaConLaCasaNotifier, EstadoDeLaDeuda, String>(DeudaConLaCasaNotifier.new);

class DeudaConLaCasaNotifier extends Notifier<EstadoDeLaDeuda> {
  DeudaConLaCasaNotifier(this.colportorId);

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  /// Hay una lectura en curso. Es un campo y no solo el estado: la guarda tiene que cortar el segundo
  /// toque aunque llegue antes de que el estado cambie.
  var _enCurso = false;

  /// Algo cambió mientras se leía: lo leído puede estar viejo y se lee otra vez al terminar.
  var _cambioMientrasLeia = false;

  @override
  EstadoDeLaDeuda build() {
    final cambios = ref.watch(deudaConLaCasaRepositoryProvider).cambios.listen((_) => _alCambiar());
    ref.onDispose(() => unawaited(cambios.cancel()));
    // La primera lectura ya está en marcha: un «Reintentar» o un volver a la pestaña antes de que
    // arranque no abre una segunda.
    _enCurso = true;
    scheduleMicrotask(() => unawaited(_correr()));
    return const EstadoDeLaDeuda(actualizando: true);
  }

  /// Vuelve a leer la deuda, con lo último a la vista. No hace nada si ya hay una lectura en curso.
  Future<void> actualizar() async {
    if (_enCurso) return;
    _enCurso = true;
    state = EstadoDeLaDeuda(lectura: state.lectura, actualizando: true);
    await _correr();
  }

  /// La sincronización cambió algo de lo que cuenta la deuda: se lee otra vez sin parpadeo (sigue a la
  /// vista lo último). Si ya se estaba leyendo, se vuelve a leer al terminar, para no perder el cambio.
  void _alCambiar() {
    if (_enCurso) {
      _cambioMientrasLeia = true;
      return;
    }
    _enCurso = true;
    unawaited(_correr());
  }

  Future<void> _correr() async {
    try {
      do {
        _cambioMientrasLeia = false;
        await _leerUnaVez();
      } while (_cambioMientrasLeia && ref.mounted);
    } finally {
      _enCurso = false;
    }
  }

  Future<void> _leerUnaVez() async {
    try {
      final resultado = await ref.read(deudaConLaCasaRepositoryProvider).leer(colportorId);
      if (!ref.mounted) return;
      state = resultado.fold(
        (falla) => EstadoDeLaDeuda(lectura: state.lectura, fallo: FalloDeLaDeuda.noDisponible),
        (lectura) => lectura == null
            ? const EstadoDeLaDeuda(fallo: FalloDeLaDeuda.sinConexion)
            : EstadoDeLaDeuda(lectura: lectura),
      );
    } on Object {
      // El repositorio no lanza; si algo se escapa, la lectura no queda trabada en «actualizando».
      if (ref.mounted) {
        state = EstadoDeLaDeuda(lectura: state.lectura, fallo: FalloDeLaDeuda.noDisponible);
      }
    }
  }
}

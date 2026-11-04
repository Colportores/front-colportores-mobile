import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../../core/config/config_supabase.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../data/datasources/deuda_con_la_casa_cache_data_source.dart';
import '../../data/datasources/deuda_con_la_casa_remote_data_source.dart';
import '../../data/repositories/deuda_con_la_casa_repository_impl.dart';
import '../../domain/entities/deuda_con_la_casa.dart';
import '../../domain/repositories/deuda_con_la_casa_repository.dart';
import 'cuenta_providers.dart';

// Cableado de la deuda con la casa editora (HU-CTA-002, vista 33B). Presentation conoce domain; data
// se inyecta acá.

/// De dónde sale la deuda: el RPC `mi_deuda_con_la_casa_editora()` con la sesión de la app. Sin
/// Supabase (tests, demo) no hay servidor: se comporta como sin conexión.
final deudaConLaCasaRemotoProvider = Provider<DeudaConLaCasaRemoteDataSource>(
  (ref) => ConfigSupabase.configurada
      ? DeudaConLaCasaSupabase.conCliente(Supabase.instance.client)
      : const DeudaConLaCasaSinServidor(),
);

/// Dónde queda la última respuesta: la tabla `deuda_casa_cache` de la DB local. Sin DB abierta no se
/// guarda nada.
final deudaConLaCasaCacheProvider = Provider<DeudaConLaCasaCacheDataSource>((ref) {
  final db = ref.watch(dbLocalProvider);
  return db == null ? const DeudaConLaCasaSinCache() : DeudaConLaCasaCacheDrift(db);
});

/// El repositorio de la deuda: el servidor manda y el teléfono se acuerda de lo último. La hora de
/// la lectura sale del reloj de Mi Cuenta ([relojCuentaProvider]).
final deudaConLaCasaRepositoryProvider = Provider<DeudaConLaCasaRepository>(
  (ref) => DeudaConLaCasaRepositoryImpl(
    ref.watch(deudaConLaCasaRemotoProvider),
    ref.watch(deudaConLaCasaCacheProvider),
    ahora: ref.watch(relojCuentaProvider),
  ),
);

/// Por qué la última lectura no llegó.
enum FalloDeLaDeuda {
  /// No había conexión.
  sinConexion,

  /// El servidor no pudo contarla o contestó algo que la app no entiende.
  noDisponible,
}

/// Lo que sabe la pantalla de la deuda con la casa editora: lo último que llegó (de ahora o guardado)
/// y si se está pidiendo de nuevo o la última lectura falló.
final class EstadoDeLaDeuda extends Equatable {
  const EstadoDeLaDeuda({this.lectura, this.actualizando = false, this.fallo});

  /// Lo último que dijo el servidor, con su hora. `null` = nunca llegó nada.
  final LecturaDeLaDeuda? lectura;

  /// Se está pidiendo al servidor.
  final bool actualizando;

  /// Por qué falló la última lectura; `null` si no falló (o si todavía se está pidiendo).
  final FalloDeLaDeuda? fallo;

  @override
  List<Object?> get props => [lectura, actualizando, fallo];
}

/// La deuda del colportor [colportorId] con la casa editora.
///
/// Al abrirse muestra lo guardado enseguida y pide la deuda al servidor; si el pedido falla, lo
/// guardado queda a la vista con el aviso de su hora, y sin nada guardado es el error con «Reintentar».
/// Es compartido por la tarjeta de Mi Cuenta y por la pantalla 33B: pedir dos veces a la vez cuenta
/// como una.
final deudaConLaCasaProvider = NotifierProvider.autoDispose
    .family<DeudaConLaCasaNotifier, EstadoDeLaDeuda, String>(DeudaConLaCasaNotifier.new);

class DeudaConLaCasaNotifier extends Notifier<EstadoDeLaDeuda> {
  DeudaConLaCasaNotifier(this.colportorId);

  /// UUID del colportor con la sesión iniciada.
  final String colportorId;

  /// Hay un pedido al servidor en curso. Es un campo y no solo el estado: la guarda tiene que cortar
  /// el segundo toque aunque llegue antes de que el estado cambie.
  var _enCurso = false;

  @override
  EstadoDeLaDeuda build() {
    // El primer pedido ya está en marcha: un «Reintentar» o un volver a la pestaña antes de que
    // arranque no abre un segundo.
    _enCurso = true;
    scheduleMicrotask(_arrancar);
    return const EstadoDeLaDeuda(actualizando: true);
  }

  Future<void> _arrancar() async {
    final repo = ref.read(deudaConLaCasaRepositoryProvider);
    final guardada = await repo.ultimaGuardada(colportorId);
    if (!ref.mounted) return;
    state = EstadoDeLaDeuda(lectura: guardada, actualizando: true);
    await _pedir(repo);
  }

  /// Vuelve a pedir la deuda al servidor, con lo último a la vista. No hace nada si ya hay un pedido
  /// en curso.
  Future<void> actualizar() async {
    if (_enCurso) return;
    _enCurso = true;
    state = EstadoDeLaDeuda(lectura: state.lectura, actualizando: true);
    await _pedir(ref.read(deudaConLaCasaRepositoryProvider));
  }

  Future<void> _pedir(DeudaConLaCasaRepository repo) async {
    try {
      final resultado = await repo.leer(colportorId);
      if (!ref.mounted) return;
      state = resultado.fold(
        (falla) => EstadoDeLaDeuda(
          lectura: state.lectura,
          fallo: falla is FailureDeudaSinConexion
              ? FalloDeLaDeuda.sinConexion
              : FalloDeLaDeuda.noDisponible,
        ),
        (lectura) => EstadoDeLaDeuda(lectura: lectura),
      );
    } on Object {
      // El repositorio no lanza; si algo se escapa, el pedido no queda trabado en «actualizando».
      if (ref.mounted) {
        state = EstadoDeLaDeuda(lectura: state.lectura, fallo: FalloDeLaDeuda.noDisponible);
      }
    } finally {
      _enCurso = false;
    }
  }
}

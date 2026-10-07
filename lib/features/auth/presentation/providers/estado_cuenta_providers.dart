import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/config/config_supabase.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/secure_storage_providers.dart';
import '../../data/datasources/estado_cuenta_local_data_source.dart';
import '../../data/datasources/estado_cuenta_remote_data_source.dart';
import '../../data/datasources/fakes/estado_cuenta_en_memoria.dart';
import '../../data/repositories/cuenta_repository_impl.dart';
import '../../domain/entities/estado_cuenta.dart';
import '../../domain/repositories/cuenta_repository.dart';
import '../../domain/usecases/consultar_estado_cuenta_use_case.dart';
import 'asignacion_campania_providers.dart';
import 'sesion_notifier.dart';

part 'estado_cuenta_providers.g.dart';

// Cableado del estado de cuenta (HU-AUTH-008). Como el remoto de auth: con Supabase, la fuente
// real; sin Supabase (tests, demo), en memoria con la cuenta activa.

/// Hasta que el BFF exponga el estado de cuenta (#62), con Supabase no hay fuente: ver
/// [EstadoCuentaSinFuente].
@Riverpod(keepAlive: true)
EstadoCuentaRemoteDataSource estadoCuentaRemoteDataSource(Ref ref) =>
    ConfigSupabase.configurada ? EstadoCuentaSinFuente() : EstadoCuentaEnMemoria();

@Riverpod(keepAlive: true)
EstadoCuentaLocalDataSource estadoCuentaLocalDataSource(Ref ref) => ConfigSupabase.configurada
    ? EstadoCuentaEnAlmacen(ref.watch(almacenSeguroProvider))
    : EstadoCuentaLocalEnMemoria();

@Riverpod(keepAlive: true)
CuentaRepository cuentaRepository(Ref ref) => CuentaRepositoryImpl(
  ref.watch(estadoCuentaRemoteDataSourceProvider),
  ref.watch(estadoCuentaLocalDataSourceProvider),
  ahora: ref.watch(ahoraEsperaProvider),
);

@Riverpod(keepAlive: true)
ConsultarEstadoCuentaUseCase consultarEstadoCuentaUseCase(Ref ref) =>
    ConsultarEstadoCuentaUseCase(ref.watch(cuentaRepositoryProvider));

/// Sin reintento automático: el caso de uso ya pone el tope de 15 s al entrar y la pantalla ofrece
/// «Reintentar». Con el reintento por defecto de Riverpod 3 (10 intentos con espera creciente) el
/// aviso de sin conexión salía a los ~203 s en vez de a los 15 s (#278).
Duration? _sinReintentos(int intento, Object error) => null;

/// Estado de la cuenta de quien tiene la sesión (HU-AUTH-008): `null` sin sesión. Se consulta al
/// entrar y al reabrir la app (con el último conocido si no hay red) y al refrescar a mano. Si
/// nunca se pudo consultar, queda en error con el [Failure].
@Riverpod(keepAlive: true, retry: _sinReintentos)
class EstadoCuentaNotifier extends _$EstadoCuentaNotifier {
  /// Número de la consulta de arranque en curso: la respuesta tardía de una anterior no cuenta.
  int _arranque = 0;

  /// Cuántos «Reintentar» a mano están consultando ahora.
  int _refrescos = 0;

  @override
  Future<EstadoCuenta?> build() async {
    final arranque = ++_arranque;
    final sesion = await ref.watch(sesionProvider.future);
    if (sesion == null) return null;
    final resultado = await ref.read(consultarEstadoCuentaUseCaseProvider)(
      ConsultarEstadoCuentaParams(
        usuarioId: sesion.usuarioId,
        admiteUltimoConocido: true,
        alLlegarTarde: (estado) => _aplicarRespuestaTardia(arranque, sesion.usuarioId, estado),
      ),
    );
    return resultado.fold((falla) => throw falla, (estado) => estado);
  }

  /// La respuesta que llegó después del tope de 15 s del arranque (decisión del agente de
  /// decisiones, #278). Se aplica solo si la persona sigue en la vista 18 (sin estado conocido,
  /// pendiente o suspendida), no hay un «Reintentar» consultando y la sesión es la misma: ahí
  /// la pantalla cambia sola. Si ya entró a su inicio con el último estado conocido, no la saca de
  /// ahí: queda guardada para el próximo arranque (la guarda el repositorio).
  void _aplicarRespuestaTardia(int arranque, String usuarioId, EstadoCuenta estado) {
    if (!ref.mounted || arranque != _arranque || _refrescos > 0) return;
    if (ref.read(sesionProvider).value?.usuarioId != usuarioId) return;
    final enLaVista18 = switch (state) {
      AsyncError() => true,
      AsyncData(value: final actual?) => !actual.accedeAModulosDeCampo,
      _ => false,
    };
    if (enLaVista18) state = AsyncData(estado);
  }

  /// Vuelve a consultar al backend (pull-to-refresh o "Actualizar"). Devuelve el [Failure] si no
  /// se pudo (el estado queda como estaba; si nunca se conoció, el error pasa a ser el de esta
  /// falla, para que Configuración diga lo mismo que la pantalla de espera) o `null` si se
  /// consultó.
  Future<Failure?> refrescar() async {
    final sesion = ref.read(sesionProvider).value;
    if (sesion == null) return null;
    _refrescos++;
    try {
      final resultado = await ref.read(consultarEstadoCuentaUseCaseProvider)(
        ConsultarEstadoCuentaParams(usuarioId: sesion.usuarioId, admiteUltimoConocido: false),
      );
      return resultado.fold(
        (falla) {
          if (state.hasError) state = AsyncError<EstadoCuenta?>(falla, StackTrace.current);
          return falla;
        },
        (estado) {
          state = AsyncData(estado);
          return null;
        },
      );
    } finally {
      _refrescos--;
    }
  }
}

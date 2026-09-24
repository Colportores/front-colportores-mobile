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
);

@Riverpod(keepAlive: true)
ConsultarEstadoCuentaUseCase consultarEstadoCuentaUseCase(Ref ref) =>
    ConsultarEstadoCuentaUseCase(ref.watch(cuentaRepositoryProvider));

/// Estado de la cuenta de quien tiene la sesión (HU-AUTH-008): `null` sin sesión. Se consulta al
/// entrar y al reabrir la app (con el último conocido si no hay red) y al refrescar a mano. Si
/// nunca se pudo consultar, queda en error con el [Failure].
@Riverpod(keepAlive: true)
class EstadoCuentaNotifier extends _$EstadoCuentaNotifier {
  @override
  Future<EstadoCuenta?> build() async {
    final sesion = await ref.watch(sesionProvider.future);
    if (sesion == null) return null;
    final resultado = await ref.read(consultarEstadoCuentaUseCaseProvider)(
      ConsultarEstadoCuentaParams(usuarioId: sesion.usuarioId, admiteUltimoConocido: true),
    );
    return resultado.fold((falla) => throw falla, (estado) => estado);
  }

  /// Vuelve a consultar al backend (pull-to-refresh o "Actualizar"). Devuelve el [Failure] si no
  /// se pudo (el estado queda como estaba) o `null` si se consultó.
  Future<Failure?> refrescar() async {
    final sesion = ref.read(sesionProvider).value;
    if (sesion == null) return null;
    final resultado = await ref.read(consultarEstadoCuentaUseCaseProvider)(
      ConsultarEstadoCuentaParams(usuarioId: sesion.usuarioId, admiteUltimoConocido: false),
    );
    return resultado.fold((falla) => falla, (estado) {
      state = AsyncData(estado);
      return null;
    });
  }
}

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/config_supabase.dart';
import '../../data/datasources/auth_local_data_source.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/datasources/auth_remote_data_source_supabase.dart';
import '../../data/datasources/fakes/auth_data_sources_en_memoria.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/cerrar_sesion_use_case.dart';
import '../../domain/usecases/iniciar_sesion_con_google_use_case.dart';
import '../../domain/usecases/iniciar_sesion_use_case.dart';
import '../../domain/usecases/obtener_sesion_actual_use_case.dart';
import '../../domain/usecases/registrar_usuario_use_case.dart';

part 'auth_providers.g.dart';

// Cableado de la feature (ADR-009): presentation conoce domain; data se inyecta acá.
// El data source local no tiene implementación por defecto: `main.dart` (y los tests) lo
// sobreescriben con `overrideWithValue`. Así ninguna feature puede "olvidarse" de inyectar.

/// Remoto real si la app se compiló con `SUPABASE_URL`/`SUPABASE_ANON_KEY` (`main.dart` ya
/// llamó a `Supabase.initialize`); si no, el fake en memoria con la cuenta demo — tests, CI sin
/// variables y la demo sin backend siguen funcionando igual (HU-AUTH-003, #22).
@Riverpod(keepAlive: true)
AuthRemoteDataSource authRemoteDataSource(Ref ref) => ConfigSupabase.configurada
    ? AuthRemoteDataSourceSupabase(Supabase.instance.client.auth)
    : AuthRemoteDataSourceEnMemoria.demo();

@Riverpod(keepAlive: true)
AuthLocalDataSource authLocalDataSource(Ref ref) {
  throw UnimplementedError('authLocalDataSourceProvider se sobreescribe en main.dart');
}

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) => AuthRepositoryImpl(
  ref.watch(authRemoteDataSourceProvider),
  ref.watch(authLocalDataSourceProvider),
);

@riverpod
IniciarSesionUseCase iniciarSesionUseCase(Ref ref) =>
    IniciarSesionUseCase(ref.watch(authRepositoryProvider));

@riverpod
IniciarSesionConGoogleUseCase iniciarSesionConGoogleUseCase(Ref ref) =>
    IniciarSesionConGoogleUseCase(ref.watch(authRepositoryProvider));

@riverpod
RegistrarUsuarioUseCase registrarUsuarioUseCase(Ref ref) =>
    RegistrarUsuarioUseCase(ref.watch(authRepositoryProvider));

@riverpod
ObtenerSesionActualUseCase obtenerSesionActualUseCase(Ref ref) =>
    ObtenerSesionActualUseCase(ref.watch(authRepositoryProvider));

@riverpod
CerrarSesionUseCase cerrarSesionUseCase(Ref ref) =>
    CerrarSesionUseCase(ref.watch(authRepositoryProvider));

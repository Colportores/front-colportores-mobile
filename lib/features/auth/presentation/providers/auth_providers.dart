import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/datasources/auth_local_data_source.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/cerrar_sesion_use_case.dart';
import '../../domain/usecases/iniciar_sesion_use_case.dart';
import '../../domain/usecases/obtener_sesion_actual_use_case.dart';

part 'auth_providers.g.dart';

// Cableado de la feature (ADR-009): presentation conoce domain; data se inyecta acá.
// Los data sources no tienen implementación por defecto: `main.dart` (y los tests) los
// sobreescriben con `overrideWithValue`. Así ninguna feature puede "olvidarse" de inyectar.

@Riverpod(keepAlive: true)
AuthRemoteDataSource authRemoteDataSource(Ref ref) {
  throw UnimplementedError('authRemoteDataSourceProvider se sobreescribe en main.dart');
}

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
ObtenerSesionActualUseCase obtenerSesionActualUseCase(Ref ref) =>
    ObtenerSesionActualUseCase(ref.watch(authRepositoryProvider));

@riverpod
CerrarSesionUseCase cerrarSesionUseCase(Ref ref) =>
    CerrarSesionUseCase(ref.watch(authRepositoryProvider));

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/config_supabase.dart';
import '../../../../core/usecases/use_case.dart';
import '../../data/datasources/auth_local_data_source.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/datasources/auth_remote_data_source_supabase.dart';
import '../../data/datasources/fakes/auth_data_sources_en_memoria.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/cerrar_sesion_use_case.dart';
import '../../domain/usecases/iniciar_sesion_con_google_use_case.dart';
import '../../domain/usecases/iniciar_sesion_use_case.dart';
import '../../domain/usecases/observar_errores_verificacion_use_case.dart';
import '../../domain/usecases/obtener_sesion_actual_use_case.dart';
import '../../domain/usecases/reenviar_verificacion_use_case.dart';
import '../../domain/usecases/registrar_usuario_use_case.dart';
import '../../domain/usecases/solicitar_recuperacion_password_use_case.dart';

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

// Los casos de uso que usa `SesionNotifier` son `keepAlive` porque él lo es: un provider que vive
// toda la app no puede depender de uno autoDispose (riverpod_lint,
// `only_use_keep_alive_inside_keep_alive`) — con `ref.read` el autoDispose se crea y se tira en
// cada llamada. Son envoltorios sin estado del repositorio (que ya es `keepAlive`): no retienen
// nada más que esa referencia.
@Riverpod(keepAlive: true)
IniciarSesionUseCase iniciarSesionUseCase(Ref ref) =>
    IniciarSesionUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
IniciarSesionConGoogleUseCase iniciarSesionConGoogleUseCase(Ref ref) =>
    IniciarSesionConGoogleUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
RegistrarUsuarioUseCase registrarUsuarioUseCase(Ref ref) =>
    RegistrarUsuarioUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
ObtenerSesionActualUseCase obtenerSesionActualUseCase(Ref ref) =>
    ObtenerSesionActualUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
CerrarSesionUseCase cerrarSesionUseCase(Ref ref) =>
    CerrarSesionUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
ReenviarVerificacionUseCase reenviarVerificacionUseCase(Ref ref) =>
    ReenviarVerificacionUseCase(ref.watch(authRepositoryProvider));

// autoDispose: no lo usa `SesionNotifier`.
@riverpod
SolicitarRecuperacionPasswordUseCase solicitarRecuperacionPasswordUseCase(Ref ref) =>
    SolicitarRecuperacionPasswordUseCase(ref.watch(authRepositoryProvider));

/// Kept-alive porque la raíz de la app (`ColportoresApp`) se suscribe una sola vez, para toda la
/// vida de la app, a `erroresVerificacionEmailProvider` (el `StreamProvider` que envuelve este
/// caso de uso) — sin `keepAlive`, Riverpod lo tiraría abajo entre rebuilds sin nadie mirándolo.
@Riverpod(keepAlive: true)
ObservarErroresVerificacionUseCase observarErroresVerificacionUseCase(Ref ref) =>
    ObservarErroresVerificacionUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
Stream<void> erroresVerificacionEmail(Ref ref) =>
    ref.watch(observarErroresVerificacionUseCaseProvider)(const NoParams());

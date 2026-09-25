import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/config_supabase.dart';
import '../../../../core/usecases/use_case.dart';
import '../../data/datasources/auth_remote_data_source_supabase.dart';
import '../../data/datasources/fakes/recuperacion_password_en_memoria.dart';
import '../../data/datasources/recuperacion_password_remote_data_source.dart';
import '../../data/repositories/recuperacion_password_repository_impl.dart';
import '../../domain/entities/enlace_recuperacion.dart';
import '../../domain/repositories/recuperacion_password_repository.dart';
import '../../domain/usecases/abandonar_recuperacion_password_use_case.dart';
import '../../domain/usecases/confirmar_recuperacion_password_use_case.dart';
import '../../domain/usecases/observar_enlaces_recuperacion_use_case.dart';
import 'db_local_providers.dart';

part 'recuperacion_password_providers.g.dart';

// Cableado de la confirmación de recuperación de contraseña (HU-AUTH-005). Aparte de
// `auth_providers.dart`: tiene su propio repositorio y además toca la DB local (re-envuelve la DEK).

/// Supabase real si la app se compiló con sus variables; si no, el fake en memoria (sin deep links:
/// la demo no puede completar una recuperación).
@Riverpod(keepAlive: true)
RecuperacionPasswordRemoteDataSource recuperacionPasswordRemoteDataSource(Ref ref) =>
    ConfigSupabase.configurada
    ? AuthRemoteDataSourceSupabase(Supabase.instance.client.auth)
    : RecuperacionPasswordEnMemoria();

@Riverpod(keepAlive: true)
RecuperacionPasswordRepository recuperacionPasswordRepository(Ref ref) =>
    RecuperacionPasswordRepositoryImpl(ref.watch(recuperacionPasswordRemoteDataSourceProvider));

/// `keepAlive` porque la raíz de la app se suscribe una sola vez, para toda su vida, a
/// [enlacesRecuperacionProvider] (igual que a los errores de verificación de email).
@Riverpod(keepAlive: true)
ObservarEnlacesRecuperacionUseCase observarEnlacesRecuperacionUseCase(Ref ref) =>
    ObservarEnlacesRecuperacionUseCase(ref.watch(recuperacionPasswordRepositoryProvider));

/// Una llegada de un enlace de recuperación. **Sin `==` a propósito**: `ref.listen` solo avisa si
/// el valor cambió, y dos enlaces válidos seguidos (el colportor pidió otro sin cerrar la app) son
/// dos llegadas. Con el enum pelado, el segundo no abría la pantalla y la sesión de recuperación
/// quedaba guardada sin que nadie fijara una contraseña (revisión de #112).
final class LlegadaEnlaceRecuperacion {
  LlegadaEnlaceRecuperacion(this.enlace);

  final EnlaceRecuperacion enlace;
}

@Riverpod(keepAlive: true)
Stream<LlegadaEnlaceRecuperacion> enlacesRecuperacion(Ref ref) => ref
    .watch(observarEnlacesRecuperacionUseCaseProvider)(const NoParams())
    .map(LlegadaEnlaceRecuperacion.new);

@riverpod
ConfirmarRecuperacionPasswordUseCase confirmarRecuperacionPasswordUseCase(Ref ref) =>
    ConfirmarRecuperacionPasswordUseCase(
      ref.watch(recuperacionPasswordRepositoryProvider),
      ref.watch(dbLocalRepositoryProvider),
      ref.watch(turnoDbLocalProvider),
    );

@riverpod
AbandonarRecuperacionPasswordUseCase abandonarRecuperacionPasswordUseCase(Ref ref) =>
    AbandonarRecuperacionPasswordUseCase(ref.watch(recuperacionPasswordRepositoryProvider));

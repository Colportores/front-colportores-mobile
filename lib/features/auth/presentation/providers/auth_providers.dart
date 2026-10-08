import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/config_supabase.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/secure_storage/secure_storage_providers.dart';
import '../../../../core/usecases/use_case.dart';
import '../../data/datasources/almacen_sesion_supabase.dart';
import '../../data/datasources/auth_local_data_source.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/datasources/auth_remote_data_source_supabase.dart';
import '../../data/datasources/backup_drive_data_source.dart';
import '../../data/datasources/fakes/auth_data_sources_en_memoria.dart';
import '../../data/datasources/reloj_sesion_en_almacen.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import '../../data/repositories/cierre_forzado_repository_impl.dart';
import '../../data/repositories/datos_locales_repository_impl.dart';
import '../../data/repositories/ultimo_correo_repository_impl.dart';
import '../../data/repositories/ultimo_envio_recuperacion_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/bloqueo_reenvio_verificacion_repository.dart';
import '../../domain/repositories/cierre_forzado_repository.dart';
import '../../domain/repositories/datos_locales_repository.dart';
import '../../domain/repositories/ultimo_correo_repository.dart';
import '../../domain/repositories/ultimo_envio_recuperacion_repository.dart';
import '../../domain/services/reloj_sesion.dart';
import '../../domain/usecases/bloqueo_reenvio_verificacion_use_cases.dart';
import '../../domain/usecases/borrar_datos_locales_use_case.dart';
import '../../domain/usecases/cerrar_sesion_use_case.dart';
import '../../domain/usecases/confirmar_password_use_case.dart';
import '../../domain/usecases/espera_recuperacion_use_cases.dart';
import '../../domain/usecases/expiraciones_sesion_use_cases.dart';
import '../../domain/usecases/iniciar_sesion_use_case.dart';
import '../../domain/usecases/observar_errores_verificacion_use_case.dart';
import '../../domain/usecases/observar_verificaciones_exitosas_use_case.dart';
import '../../domain/usecases/obtener_resumen_datos_locales_use_case.dart';
import '../../domain/usecases/obtener_sesion_actual_use_case.dart';
import '../../domain/usecases/reenviar_verificacion_use_case.dart';
import '../../domain/usecases/registrar_usuario_use_case.dart';
import '../../domain/usecases/reintentar_revocacion_pendiente_use_case.dart';
import '../../domain/usecases/renovar_sesion_use_case.dart';
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
    ? AuthRemoteDataSourceSupabase(
        Supabase.instance.client.auth,
        sesionPersistida: ref.watch(almacenSesionSupabaseProvider),
      )
    : AuthRemoteDataSourceEnMemoria.demo();

/// Dónde guarda `supabase_flutter` la sesión (HU-AUTH-007). La misma instancia que `main.dart` le
/// pasa a `Supabase.initialize`, que la sobreescribe acá; sin Supabase no se usa.
@Riverpod(keepAlive: true)
AlmacenSesionSupabase almacenSesionSupabase(Ref ref) {
  throw UnimplementedError('almacenSesionSupabaseProvider se sobreescribe en main.dart');
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

// Los casos de uso que usa `SesionNotifier` son `keepAlive` porque él lo es: un provider que vive
// toda la app no puede depender de uno autoDispose (riverpod_lint,
// `only_use_keep_alive_inside_keep_alive`) — con `ref.read` el autoDispose se crea y se tira en
// cada llamada. Son envoltorios sin estado del repositorio (que ya es `keepAlive`): no retienen
// nada más que esa referencia.
@Riverpod(keepAlive: true)
IniciarSesionUseCase iniciarSesionUseCase(Ref ref) =>
    IniciarSesionUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
RegistrarUsuarioUseCase registrarUsuarioUseCase(Ref ref) =>
    RegistrarUsuarioUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
ObtenerSesionActualUseCase obtenerSesionActualUseCase(Ref ref) =>
    ObtenerSesionActualUseCase(ref.watch(authRepositoryProvider), ref.watch(relojSesionProvider));

/// Reloj de la ventana de la sesión (HU-AUTH-007). En el equipo, `main.dart` lo sobreescribe con
/// el que recuerda en el almacén seguro el instante más alto visto (la misma instancia que usa
/// `AlmacenSesionSupabase`); por defecto (tests), en memoria.
@Riverpod(keepAlive: true)
RelojSesion relojSesion(Ref ref) => RelojSesionEnMemoria();

/// El correo de la última cuenta (decisión de Cristian, 01/10). En el equipo, `main.dart` lo
/// sobreescribe con el almacén seguro; por defecto (tests), en memoria.
@Riverpod(keepAlive: true)
UltimoCorreoRepository ultimoCorreoRepository(Ref ref) => UltimoCorreoEnMemoria();

/// El motivo y la fecha del último cierre de sesión que la persona no pidió (decisión de Cristian,
/// 07/10, #302): el aviso de «Sesión vencida» vale en cada arranque sin sesión hasta que entra. En
/// el equipo, `main.dart` lo sobreescribe con el almacén seguro; por defecto (tests), en memoria.
@Riverpod(keepAlive: true)
CierreForzadoRepository cierreForzadoRepository(Ref ref) => CierreForzadoEnMemoria();

/// Cuándo salió el último enlace de recuperación de contraseña pedido desde este teléfono (decisión
/// de Cristian, 02/10, #223; seguimiento #281): la espera de 60 s de «Olvidé mi contraseña» no se
/// reinicia al salir y volver a entrar. En el equipo, `main.dart` lo sobreescribe con el almacén
/// seguro; por defecto (tests), en memoria.
@Riverpod(keepAlive: true)
UltimoEnvioRecuperacionRepository ultimoEnvioRecuperacionRepository(Ref ref) =>
    UltimoEnvioRecuperacionEnMemoria();

/// Los correos con el reenvío del email de verificación bloqueado y hasta cuándo (decisión de
/// Cristian, 30/09, #221 y #239; seguimiento #249): el candado de 60 minutos es por dirección y
/// sobrevive a reiniciar la app. En el equipo, `main.dart` lo sobreescribe con el almacén seguro;
/// por defecto (tests), en memoria.
@Riverpod(keepAlive: true)
BloqueoReenvioVerificacionRepository bloqueoReenvioVerificacionRepository(Ref ref) =>
    BloqueoReenvioVerificacionEnMemoria();

@Riverpod(keepAlive: true)
CerrarSesionUseCase cerrarSesionUseCase(Ref ref) =>
    CerrarSesionUseCase(ref.watch(authRepositoryProvider));

/// Refresh del JWT para el resto de la app (HU-AUTH-007; el motor de sync lo usa ante un `401`).
@Riverpod(keepAlive: true)
RenovarSesionUseCase renovarSesionUseCase(Ref ref) =>
    RenovarSesionUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
ObservarExpiracionesSesionUseCase observarExpiracionesSesionUseCase(Ref ref) =>
    ObservarExpiracionesSesionUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
ExpirarSesionUseCase expirarSesionUseCase(Ref ref) =>
    ExpirarSesionUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
ReenviarVerificacionUseCase reenviarVerificacionUseCase(Ref ref) =>
    ReenviarVerificacionUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
ReintentarRevocacionPendienteUseCase reintentarRevocacionPendienteUseCase(Ref ref) =>
    ReintentarRevocacionPendienteUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
ConfirmarPasswordUseCase confirmarPasswordUseCase(Ref ref) =>
    ConfirmarPasswordUseCase(ref.watch(authRepositoryProvider));

/// Backup en Drive (#184 y #185, HU-SYNC-004/005): hasta que exista, [BackupDriveNoDisponible].
@Riverpod(keepAlive: true)
BackupDriveDataSource backupDriveDataSource(Ref ref) => const BackupDriveNoDisponible();

/// Los datos del teléfono como un todo (HU-AUTH-006/010). La DB se lee y se cierra a través de
/// `dbLocalProvider`, la única puerta de entrada a ella.
@Riverpod(keepAlive: true)
DatosLocalesRepository datosLocalesRepository(Ref ref) => DatosLocalesRepositoryImpl(
  ref.watch(databaseHelperProvider),
  () => ref.read(dbLocalProvider),
  () => ref.read(dbLocalProvider.notifier).cerrar(),
  ref.watch(custodiaClaveDbProvider),
  ref.watch(backupDriveDataSourceProvider),
);

@Riverpod(keepAlive: true)
BorrarDatosLocalesUseCase borrarDatosLocalesUseCase(Ref ref) => BorrarDatosLocalesUseCase(
  ref.watch(datosLocalesRepositoryProvider),
  ref.watch(authRepositoryProvider),
);

// autoDispose: no lo usa `SesionNotifier`.
@riverpod
ObtenerResumenDatosLocalesUseCase obtenerResumenDatosLocalesUseCase(Ref ref) =>
    ObtenerResumenDatosLocalesUseCase(ref.watch(datosLocalesRepositoryProvider));

// autoDispose: no lo usa `SesionNotifier`.
@riverpod
SolicitarRecuperacionPasswordUseCase solicitarRecuperacionPasswordUseCase(Ref ref) =>
    SolicitarRecuperacionPasswordUseCase(ref.watch(authRepositoryProvider));

// autoDispose: lo usa solo `RecuperacionPasswordPage`.
@riverpod
ConsultarEsperaRecuperacionUseCase consultarEsperaRecuperacionUseCase(Ref ref) =>
    ConsultarEsperaRecuperacionUseCase(ref.watch(ultimoEnvioRecuperacionRepositoryProvider));

// autoDispose: lo usa solo `RecuperacionPasswordPage`.
@riverpod
RegistrarEnvioRecuperacionUseCase registrarEnvioRecuperacionUseCase(Ref ref) =>
    RegistrarEnvioRecuperacionUseCase(ref.watch(ultimoEnvioRecuperacionRepositoryProvider));

// autoDispose: lo usa solo `VerificacionEmailPage`.
@riverpod
ConsultarBloqueosReenvioVerificacionUseCase consultarBloqueosReenvioVerificacionUseCase(Ref ref) =>
    ConsultarBloqueosReenvioVerificacionUseCase(
      ref.watch(bloqueoReenvioVerificacionRepositoryProvider),
    );

// autoDispose: lo usa solo `VerificacionEmailPage`.
@riverpod
RegistrarBloqueoReenvioVerificacionUseCase registrarBloqueoReenvioVerificacionUseCase(Ref ref) =>
    RegistrarBloqueoReenvioVerificacionUseCase(
      ref.watch(bloqueoReenvioVerificacionRepositoryProvider),
    );

/// Kept-alive porque la raíz de la app (`ColportoresApp`) se suscribe una sola vez, para toda la
/// vida de la app, a `erroresVerificacionEmailProvider` (el `StreamProvider` que envuelve este
/// caso de uso) — sin `keepAlive`, Riverpod lo tiraría abajo entre rebuilds sin nadie mirándolo.
@Riverpod(keepAlive: true)
ObservarErroresVerificacionUseCase observarErroresVerificacionUseCase(Ref ref) =>
    ObservarErroresVerificacionUseCase(ref.watch(authRepositoryProvider));

/// Un evento de verificación de email (un error o un éxito). **Sin `==` a propósito**, y sin
/// constructor `const` (dos `const` iguales serían la misma instancia): `ref.listen` solo avisa si
/// el valor cambió, y con `Stream<void>` todos los eventos valían `AsyncData(null)`, así que el
/// listener de la raíz veía el primero y se perdía los siguientes (#126). Mismo criterio que
/// `LlegadaEnlaceRecuperacion`.
final class EventoVerificacionEmail {}

@Riverpod(keepAlive: true)
Stream<EventoVerificacionEmail> erroresVerificacionEmail(Ref ref) => ref
    .watch(observarErroresVerificacionUseCaseProvider)(const NoParams())
    .map((_) => EventoVerificacionEmail());

/// Kept-alive por el mismo motivo que `erroresVerificacionEmailProvider`: la raíz de la app se
/// suscribe una sola vez, para toda la vida de la app.
@Riverpod(keepAlive: true)
ObservarVerificacionesExitosasUseCase observarVerificacionesExitosasUseCase(Ref ref) =>
    ObservarVerificacionesExitosasUseCase(ref.watch(authRepositoryProvider));

@Riverpod(keepAlive: true)
Stream<EventoVerificacionEmail> verificacionesExitosas(Ref ref) => ref
    .watch(observarVerificacionesExitosasUseCaseProvider)(const NoParams())
    .map((_) => EventoVerificacionEmail());

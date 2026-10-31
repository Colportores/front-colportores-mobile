import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/conectividad/conectividad_providers.dart';
import 'core/conectividad/monitor_conectividad_plus.dart';
import 'core/config/config_google.dart';
import 'core/config/config_supabase.dart';
import 'core/database/database_helper.dart';
import 'core/database/database_providers.dart';
import 'core/dispositivo/dispositivo_providers.dart';
import 'core/dispositivo/orientacion_app.dart';
import 'core/dispositivo/seguridad_dispositivo_canal.dart';
import 'core/logging/app_logger.dart';
import 'core/notificaciones/notificaciones_providers.dart';
import 'core/notificaciones/permiso_notificaciones_sistema.dart';
import 'core/secure_storage/almacen_seguro_keystore.dart';
import 'core/secure_storage/archivo_envoltorio_dek.dart';
import 'core/secure_storage/secure_storage_providers.dart';
import 'core/sync/sync_providers.dart';
import 'features/agenda/data/recordatorios/motor_de_avisos_plugin.dart';
import 'features/agenda/data/recordatorios/recordatorios_locales.dart';
import 'features/agenda/presentation/flujo_agendar_visita.dart';
import 'features/agenda/presentation/flujo_detalle_agenda.dart';
import 'features/agenda/presentation/providers/recordatorios_providers.dart';
import 'features/auth/data/datasources/almacen_sesion_supabase.dart';
import 'features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'features/auth/data/datasources/registro_enlaces_auth.dart';
import 'features/auth/data/datasources/reloj_sesion_en_almacen.dart';
import 'features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import 'features/auth/data/repositories/cierre_forzado_repository_impl.dart';
import 'features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'features/auth/data/repositories/ultimo_envio_recuperacion_repository_impl.dart';
import 'features/auth/data/repositories/zonas_avisadas_repository_impl.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/auth/presentation/providers/avisos_zona_providers.dart';
import 'features/auth/presentation/providers/sesion_notifier.dart';
import 'features/cobranzas/presentation/flujo_cobrar_desde_la_casa.dart';
import 'features/cobranzas/presentation/pages/cobro_efectivo_page.dart';
import 'features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'features/configuracion/data/repositories/aviso_privacidad_repository_impl.dart';
import 'features/configuracion/presentation/providers/aviso_privacidad_providers.dart';
import 'features/mapa/presentation/flujo_registrar_visita.dart';
import 'features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'features/mapa/presentation/providers/personas_providers.dart';
import 'features/mapa/presentation/widgets/pestana_notas_de_la_casa.dart';
import 'features/notificaciones/data/repositories/marca_conciliacion_recordatorios_impl.dart';
import 'features/notificaciones/data/repositories/permiso_notificaciones_repository_impl.dart';
import 'features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'features/notificaciones/presentation/providers/conciliacion_recordatorios_providers.dart';
import 'features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'features/notificaciones/presentation/providers/preferencias_recordatorios_providers.dart';
import 'features/respaldo/data/repositories/recuperacion_resuelta_repository_impl.dart';
import 'features/respaldo/data/repositories/respaldo_drive_repository_impl.dart';
import 'features/respaldo/data/services/nivel_bateria_canal.dart';
import 'features/respaldo/data/services/servicio_google.dart';
import 'features/respaldo/data/services/servicio_google_sign_in.dart';
import 'features/respaldo/presentation/providers/recuperacion_pendiente_providers.dart';
import 'features/respaldo/presentation/providers/respaldo_automatico_providers.dart';
import 'features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'features/tiles/data/composicion_tiles.dart';
import 'features/tiles/presentation/providers/mapas_offline_providers.dart';
import 'features/tiles/presentation/providers/tiles_providers.dart';
import 'features/ventas/presentation/pages/devolucion_page.dart';
import 'features/ventas/presentation/providers/ventas_providers.dart'
    show cobrarDespuesDeLaVentaProvider;
import 'plataforma/identidad_instalacion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sin PII en `toString()` (convenciones §7.5, #540): `Equatable` arranca con `stringify` en `true` en
  // debug y volcaría las `props` (calle, número, coordenadas, nombres) de cualquier entidad a un log.
  EquatableConfig.stringify = false;
  // Solo vertical (#301): la misma regla que el manifest de Android y el Info.plist de iOS.
  await OrientacionApp.fijarVertical();

  final almacenSeguro = AlmacenSeguroKeystore();
  final relojSesion = RelojSesionEnAlmacen(almacenSeguro);
  AlmacenSesionSupabase? sesionPersistida;

  if (ConfigSupabase.configurada) {
    // Supabase Auth real (HU-AUTH-003). La sesión (JWT + refresh token) la guarda supabase_flutter
    // en el almacén seguro y no en SharedPreferences, su default; la de una versión anterior se
    // migra una vez. Esa misma puerta descarta la sesión que lleva 30 días sin uso (HU-AUTH-007).
    // `publishableKey` acepta tanto la anon key legacy (JWT `eyJ…`) como las nuevas
    // `sb_publishable_…`; las dos viajan como header `apikey`.
    sesionPersistida = AlmacenSesionSupabase(
      almacenSeguro,
      relojSesion,
      anterior: SharedPreferencesLocalStorage(
        persistSessionKey: 'sb-${Uri.parse(ConfigSupabase.url).host.split('.').first}-auth-token',
      ),
    );
    await Supabase.initialize(
      url: ConfigSupabase.url,
      publishableKey: ConfigSupabase.anonKey,
      // Registra cada deep link antes de que supabase_flutter lo canjee, para saber si es de
      // verificación de email o de recuperación de contraseña (HU-AUTH-005, RegistroEnlacesAuth).
      authOptions: FlutterAuthClientOptions(
        localStorage: sesionPersistida,
        detectSessionInUriPredicate: RegistroEnlacesAuth.instancia.esCallbackDeAuth,
      ),
    );
  } else {
    AppLogger.instance.info(
      LogModulo.auth,
      'CONFIG',
      'Supabase no configurado: usando fakes en memoria',
    );
  }

  // Paquetes de mapas offline (#189): conexión real del teléfono, catálogo del bucket `mapas`,
  // descarga con Range y checksum. Si no se puede preparar la carpeta, la app arranca igual y el
  // mapa queda con el servidor online.
  // El sobre del sync (contrato-sync-engine §5.3): el id de la instalación sale del almacén seguro,
  // que es asincrónico, y el transporte lo necesita sincrónico.
  final sobreSync = await sobreDeEstaInstalacion(almacenSeguro);

  final conectividad = MonitorConectividadPlus();
  ComposicionTiles? tiles;
  try {
    tiles = await ComposicionTiles.crear(
      directorioApp: await getApplicationSupportDirectory(),
      conectividad: conectividad,
      supabaseUrl: ConfigSupabase.url,
    );
  } on Object catch (e, st) {
    AppLogger.instance.error(
      LogModulo.map,
      'main',
      'no se pudo preparar la carpeta de los mapas',
      const {},
      e,
      st,
    );
  }

  // Recordatorios locales de las visitas (HU-NOT-002): el plugin se prepara antes de la primera
  // pantalla para recoger el aviso que abrió la app, si lo hubo. Si no arranca, la app sigue.
  final permisoNotificaciones = PermisoNotificacionesCanal();
  // Las preferencias de los recordatorios (HU-NOT-004) viven en el almacén seguro; el mismo objeto
  // las lee al programar cada aviso (si están prendidos y con cuánta anticipación).
  final preferenciasRecordatorios = PreferenciasRecordatoriosRepositoryImpl(almacenSeguro);
  final recordatorios = RecordatoriosLocales(
    motor: MotorDeAvisosPlugin(FlutterLocalNotificationsPlugin()),
    permiso: permisoNotificaciones,
    anticipacion: preferenciasRecordatorios,
    activados: preferenciasRecordatorios,
  );
  await recordatorios.iniciar();

  runApp(
    ProviderScope(
      // Composición de la app: acá se eligen las implementaciones de infraestructura.
      // AuthRemoteDataSource: lo elige `authRemoteDataSourceProvider` según `ConfigSupabase`
      // (Supabase real o fake con la cuenta demo@colportores.app / demo1234).
      // Sprint 2: AuthLocalDataSource sobre secure_storage (pendiente; hoy en memoria).
      overrides: [
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        // Keystore/Keychain reales, con las opciones de ADR-006: la misma instancia que guarda la
        // sesión de Supabase. Construirlo no toca la plataforma: recién en la primera lectura o
        // escritura se cruza al canal nativo.
        almacenSeguroProvider.overrideWithValue(almacenSeguro),
        sobreSyncProvider.overrideWithValue(sobreSync),
        relojSesionProvider.overrideWithValue(relojSesion),
        // Solo el correo de la última cuenta, para «Sesión vencida» tras un arranque en frío.
        ultimoCorreoRepositoryProvider.overrideWithValue(UltimoCorreoRepositoryImpl(almacenSeguro)),
        // Al lado del correo, el motivo y la fecha del último cierre que la persona no pidió: el
        // aviso de «Sesión vencida» vale en cada arranque sin sesión hasta que entra.
        cierreForzadoRepositoryProvider.overrideWithValue(
          CierreForzadoRepositoryImpl(almacenSeguro),
        ),
        // La hora del último enlace de recuperación pedido, por teléfono: la espera de 60 s de
        // «Olvidé mi contraseña» no se reinicia al salir y volver a entrar.
        ultimoEnvioRecuperacionRepositoryProvider.overrideWithValue(
          UltimoEnvioRecuperacionRepositoryImpl(almacenSeguro),
        ),
        // Los correos con el reenvío de la verificación bloqueado: el candado de 60 minutos es por
        // dirección y sobrevive a reiniciar la app.
        bloqueoReenvioVerificacionRepositoryProvider.overrideWithValue(
          BloqueoReenvioVerificacionRepositoryImpl(almacenSeguro),
        ),
        // La zona de cada inscripción la última vez que se le avisó al colportor (HU-CAM-006,
        // #251): un cambio de zona se avisa una sola vez, aunque se cierre la app.
        zonasAvisadasRepositoryProvider.overrideWithValue(
          ZonasAvisadasRepositoryImpl(almacenSeguro),
        ),
        // El permiso de notificaciones (HU-NOT-001, vista 24): canal nativo propio (MainActivity.kt,
        // AppDelegate.swift) y, en el almacén seguro, si ya se le pidió y si cerró el aviso de Hoy.
        permisoNotificacionesSistemaProvider.overrideWithValue(permisoNotificaciones),
        // Los avisos de las visitas agendadas (HU-NOT-002), con el plugin del teléfono.
        recordatoriosProvider.overrideWithValue(recordatorios),
        toquesDeRecordatoriosProvider.overrideWithValue(recordatorios),
        preferenciasRecordatoriosRepositoryProvider.overrideWithValue(preferenciasRecordatorios),
        // Hasta dónde se guardaron en el historial los recordatorios que sonaron (HU-NOT-005).
        marcaConciliacionRecordatoriosProvider.overrideWithValue(
          MarcaConciliacionRecordatoriosImpl(almacenSeguro),
        ),
        permisoNotificacionesRepositoryProvider.overrideWithValue(
          PermisoNotificacionesRepositoryImpl(almacenSeguro),
        ),
        // HU-SYNC-006 (vista 34): el asistente de recuperación del primer arranque.
        asistenteDeRecuperacionHabilitadoProvider.overrideWithValue(true),
        recuperacionResueltaRepositoryProvider.overrideWithValue(
          RecuperacionResueltaRepositoryImpl(almacenSeguro),
        ),
        // Qué cuentas escondieron el aviso de privacidad con «No volver a mostrar» (#445, #447): es
        // por cuenta y se vuelve a encender desde Configuración.
        avisoPrivacidadRepositoryProvider.overrideWithValue(
          AvisoPrivacidadRepositoryImpl(almacenSeguro),
        ),
        // El respaldo en el Drive de la persona (HU-SYNC-004): sin los identificadores de cliente de
        // Google (`--dart-define`, docs/google-drive-oauth.md) no se puede conectar y la fila
        // «Cuenta Drive» lo dice con «No pudimos conectar tu Drive».
        // El primer respaldo al conectar (HU-SYNC-005): lo pide el repositorio cuando termina de
        // conectar, y el servicio se arma recién ahí (necesita el motor, que se arma después).
        respaldoDriveRepositoryProvider.overrideWith(
          (ref) => RespaldoDriveRepositoryImpl(
            almacenSeguro,
            ConfigGoogle.configurada ? ServicioGoogleSignIn() : const ServicioGoogleSinConfigurar(),
            primerRespaldo: PrimerRespaldoConServicio(() => ref.read(servicioRespaldoProvider)),
          ),
        ),
        // La batería para el respaldo automático (R-SY10): canal nativo propio (MainActivity.kt,
        // AppDelegate.swift).
        nivelBateriaProvider.overrideWithValue(NivelBateriaCanal()),
        if (sesionPersistida != null)
          almacenSesionSupabaseProvider.overrideWithValue(sesionPersistida),
        // DEK envuelta con la contraseña (ADR-006): archivo común, fuera del almacén seguro, en
        // el mismo directorio que la DB.
        archivoEnvoltorioDekProvider.overrideWithValue(
          ArchivoEnvoltorioDek(directorio: getApplicationDocumentsDirectory),
        ),
        // Bloqueo de pantalla y nivel del Keystore: canal nativo propio (MainActivity.kt,
        // AppDelegate.swift).
        seguridadDispositivoProvider.overrideWithValue(SeguridadDispositivoCanal()),
        monitorConectividadProvider.overrideWithValue(conectividad),
        // Lo que debe cada persona (HU-COB-001): las ventas del teléfono menos sus cobros.
        saldosDePersonasProvider.overrideWith(
          (ref) => SaldosDePersonasLocal(ref.watch(cobranzaLocalProvider)),
        ),
        // «Registrar visita» de la hoja de la casa (vista 39, #411): «¿Qué pasó?» y el aviso
        // «Guardado» con «Deshacer». Se abre sobre el navegador de la app, no sobre la hoja que se
        // cierra. «Entrevista dada» y «Cobranza» se enganchan con sus HU.
        registrarVisitaDesdeLaCasaProvider.overrideWith(
          (ref) => (datos) {
            final contexto = navigatorKeyColportores.currentContext;
            if (contexto == null) return false;
            return FlujoRegistrarVisita.abrir(
              contexto,
              datos,
              colportorId: ref.read(sesionProvider).value?.usuarioId,
            );
          },
        ),
        // «Cobrar ahora» de «Venta registrada: ¿y ahora?» (vista 27, 27A·14): el cobro en efectivo
        // (vista 28, #439) con la venta, la casa y el cliente ya resueltos.
        cobrarDespuesDeLaVentaProvider.overrideWith(
          (ref) => (cobro) async {
            final contexto = navigatorKeyColportores.currentContext;
            if (contexto == null) return false;
            return CobroEfectivoPage.abrir(
              contexto,
              ventaId: cobro.ventaId,
              colportorId: cobro.colportorId,
              espacioId: cobro.espacioId,
              espacioPersonaId: cobro.espacioPersonaId,
            );
          },
        ),
        // Tocar una venta en la ficha de la persona (vista 32 B → vista 31, HU-VEN-004): la devolución
        // de esa venta, con la venta, la casa y la persona ya resueltas. Devuelve `true` si se registró.
        devolverVentaDesdeLaFichaProvider.overrideWith(
          (ref) => (datos) {
            final contexto = navigatorKeyColportores.currentContext;
            final colportorId = ref.read(sesionProvider).value?.usuarioId;
            if (contexto == null || colportorId == null || colportorId.trim().isEmpty) return false;
            return DevolucionPage.abrir(
              contexto,
              ventaId: datos.ventaId,
              colportorId: colportorId,
              espacioId: datos.espacioId,
              personaId: datos.personaId,
            );
          },
        ),
        // «$ Cobrar» de la hoja de la casa y «Cobranza» de «¿Qué pasó?» (vista 39, C·01 y C·06, #440):
        // «¿Qué venta?» (C·08, se salta con una sola) y el cobro en efectivo (vista 28). Devuelve
        // `true` si se cobró; la visita «Cobranza» la guarda `FlujoRegistrarVisita`, no esto.
        cobrarDesdeLaCasaProvider.overrideWith(
          (ref) => (datos) {
            final contexto = navigatorKeyColportores.currentContext;
            if (contexto == null) return false;
            return FlujoCobrarDesdeLaCasa.abrir(
              contexto,
              datos,
              colportorId: ref.read(sesionProvider).value?.usuarioId,
            );
          },
        ),
        // «Programar entrevista» (vista 39, R·02): «Agendar visita» (vista 23 A, #408) con la casa y,
        // si se sabe, la persona ya resueltas. Vuelve a la hoja de la casa con la casa en amarillo.
        programarEntrevistaDesdeLaCasaProvider.overrideWith(
          (ref) => (cita) {
            final contexto = navigatorKeyColportores.currentContext;
            if (contexto == null) return false;
            return FlujoAgendarVisita.abrir(
              contexto,
              espacioId: cita.espacioId,
              espacioPersonaId: cita.espacioPersonaId,
              colportorId: ref.read(sesionProvider).value?.usuarioId,
            );
          },
        ),
        // El detalle de una agenda (vista 23, 23C·01, #409): lo abren el recordatorio tocado, el aviso
        // del centro de notificaciones y la fila de la pestaña Agenda.
        ...FlujoDetalleAgenda.enganches(navigatorKeyColportores),
        // Pestaña Notas de la hoja de la casa (vista 39, C·05, #447): las notas del lugar, todas en
        // el teléfono. La pestaña Historial se engancha con su HU (#446).
        pestanaNotasDeLaCasaProvider.overrideWithValue(
          (context, contexto) => PestanaNotasDeLaCasa(
            ubicacionId: contexto.ubicacionId,
            colportorId: contexto.colportorId,
            soloLectura: contexto.esBaja,
          ),
        ),
        if (tiles != null) ...[
          paquetesTilesRepositoryProvider.overrideWithValue(tiles.repository),
          descargadorPaquetesTilesProvider.overrideWithValue(tiles.descargador),
          sondaArchivoTilesProvider.overrideWithValue(tiles.sonda),
          medidorEspacioDiscoProvider.overrideWithValue(tiles.espacio),
        ],
        // DB local cifrada (ADR-006). Construirlo no abre nada: la abre la preparación de
        // HU-AUTH-009 (`PreparacionDbLocalNotifier`) con la DEK, vía `dbLocalProvider`, después de
        // cada login y al restaurar la sesión. El archivo vive en el directorio de documentos
        // de la app (default de drift_flutter); nombre y ruta no están fijados por la doc del
        // proyecto.
        databaseHelperProvider.overrideWithValue(
          DatabaseHelper(
            directorio: getApplicationDocumentsDirectory,
            directorioTemporal: getTemporaryDirectory,
          ),
        ),
      ],
      child: const ColportoresApp(),
    ),
  );
}

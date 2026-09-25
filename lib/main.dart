import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/config_supabase.dart';
import 'core/database/database_helper.dart';
import 'core/database/database_providers.dart';
import 'core/dispositivo/dispositivo_providers.dart';
import 'core/dispositivo/seguridad_dispositivo_canal.dart';
import 'core/logging/app_logger.dart';
import 'core/secure_storage/almacen_seguro_keystore.dart';
import 'core/secure_storage/archivo_envoltorio_dek.dart';
import 'core/secure_storage/secure_storage_providers.dart';
import 'features/auth/data/datasources/almacen_sesion_supabase.dart';
import 'features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'features/auth/data/datasources/registro_enlaces_auth.dart';
import 'features/auth/data/datasources/reloj_sesion_en_almacen.dart';
import 'features/auth/presentation/providers/auth_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
        relojSesionProvider.overrideWithValue(relojSesion),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/config_supabase.dart';
import 'core/database/database_helper.dart';
import 'core/database/database_providers.dart';
import 'core/logging/app_logger.dart';
import 'core/secure_storage/almacen_seguro_keystore.dart';
import 'core/secure_storage/secure_storage_providers.dart';
import 'features/auth/data/datasources/almacen_sesion_supabase.dart';
import 'features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
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
      authOptions: FlutterAuthClientOptions(localStorage: sesionPersistida),
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
        // Keystore/Keychain reales. Construirlo no toca la plataforma: recién en la primera
        // lectura o escritura se cruza al canal nativo.
        almacenSeguroProvider.overrideWithValue(almacenSeguro),
        relojSesionProvider.overrideWithValue(relojSesion),
        if (sesionPersistida != null)
          almacenSesionSupabaseProvider.overrideWithValue(sesionPersistida),
        // DB local cifrada (ADR-003). Construirlo no abre nada: la abre el flujo de login de
        // HU-AUTH-009 (#27) con la clave derivada, vía `dbLocalProvider`. El archivo vive en el
        // directorio de documentos de la app (default de drift_flutter); nombre y ruta no están
        // fijados por la doc del proyecto.
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

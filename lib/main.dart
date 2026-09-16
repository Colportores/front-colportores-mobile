import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/database/database_helper.dart';
import 'core/database/database_providers.dart';
import 'core/secure_storage/almacen_seguro_keystore.dart';
import 'core/secure_storage/secure_storage_providers.dart';
import 'features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'features/auth/presentation/providers/auth_providers.dart';

void main() {
  runApp(
    ProviderScope(
      // Composición de la app: acá se eligen las implementaciones de infraestructura.
      // Sprint 1: todo en memoria (cuenta demo@colportores.app / demo1234).
      // Sprint 2: AuthLocalDataSource sobre secure_storage. Sprint 3: AuthRemoteDataSource sobre Supabase.
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(AuthRemoteDataSourceEnMemoria.demo()),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        // Keystore/Keychain reales. Construirlo no toca la plataforma: recién en la primera
        // lectura o escritura se cruza al canal nativo.
        almacenSeguroProvider.overrideWithValue(AlmacenSeguroKeystore()),
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

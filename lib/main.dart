import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
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
      ],
      child: const ColportoresApp(),
    ),
  );
}

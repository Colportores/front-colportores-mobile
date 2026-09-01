import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
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
      ],
      child: const ColportoresApp(),
    ),
  );
}

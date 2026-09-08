import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/presentation/pages/inicio_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/providers/sesion_notifier.dart';

/// Raíz de la app. El router (go_router) llega con el mapa en Sprint 5; hasta entonces la
/// navegación es "hay sesión → inicio, no hay → login".
class ColportoresApp extends ConsumerWidget {
  const ColportoresApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);

    return MaterialApp(
      title: 'Colportores',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1B5E20), useMaterial3: true),
      home: sesion.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => const LoginPage(),
        data: (s) => s == null ? const LoginPage() : InicioPage(sesion: s),
      ),
    );
  }
}

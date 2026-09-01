import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/sesion.dart';
import '../providers/sesion_notifier.dart';

/// Pantalla posterior al login. Placeholder hasta que exista el mapa (Sprint 5); hoy solo
/// demuestra que la sesión está disponible para el resto de la app.
class InicioPage extends ConsumerWidget {
  const InicioPage({super.key, required this.sesion});

  final Sesion sesion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Colportores'),
        actions: [
          IconButton(
            key: const Key('inicio_cerrar_sesion'),
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sesionProvider.notifier).cerrarSesion(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 64),
            const SizedBox(height: 16),
            const Text('Sesión iniciada'),
            Text(sesion.email, key: const Key('inicio_email')),
          ],
        ),
      ),
    );
  }
}

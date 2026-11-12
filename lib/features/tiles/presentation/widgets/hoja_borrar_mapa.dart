import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../textos_mapas_offline.dart';

/// La hoja «¿Borrar el mapa de `<nombre>`?» (vista 35, 35-07 «Borrar mapa»): avisa que para volver a
/// tenerlo hace falta Wi-Fi. `true` si el colportor confirma; `false` o `null` si cancela o la
/// cierra. Mismo patrón que la hoja de «Achicar la cobertura» (35-09).
Future<bool?> mostrarHojaBorrarMapa(BuildContext context, {required String nombre}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => HojaBorrarMapa(nombre: nombre),
    );

class HojaBorrarMapa extends StatelessWidget {
  const HojaBorrarMapa({super.key, required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    return SingleChildScrollView(
      child: Padding(
        key: const Key('mapas_offline_hoja_borrar'),
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Semantics(
              header: true,
              child: Text(
                TextosMapasOffline.borrarTitulo(nombre),
                style: theme.textTheme.headlineSmall,
              ),
            ),
            Text(
              TextosMapasOffline.borrarTexto,
              style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
            ),
            FilledButton(
              key: const Key('mapas_offline_borrar_confirmar'),
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: const Text(TextosMapasOffline.borrar),
            ),
            OutlinedButton(
              key: const Key('mapas_offline_borrar_cancelar'),
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text(TextosMapasOffline.cancelar),
            ),
          ],
        ),
      ),
    );
  }
}

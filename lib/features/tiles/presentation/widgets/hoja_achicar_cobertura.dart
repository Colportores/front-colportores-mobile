import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/paquete_tiles.dart';
import '../textos_mapas_offline.dart';

/// La hoja «¿Quedarte solo con tu zona?» (vista 35, pantalla 02 «Achicar la cobertura»): avisa qué
/// mapa se borra, cuánto espacio queda libre y que fuera del mapa que se queda el mapa sin señal se
/// ve en blanco. `true` si el colportor confirma; `false` o `null` si cancela o la cierra.
Future<bool?> mostrarHojaAchicarCobertura(
  BuildContext context, {
  required NivelCobertura nivel,
  required String mayor,
  required String elegido,
  required int liberanMegabytes,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => HojaAchicarCobertura(
    nivel: nivel,
    mayor: mayor,
    elegido: elegido,
    liberanMegabytes: liberanMegabytes,
  ),
);

class HojaAchicarCobertura extends StatelessWidget {
  const HojaAchicarCobertura({
    super.key,
    required this.nivel,
    required this.mayor,
    required this.elegido,
    required this.liberanMegabytes,
  });

  final NivelCobertura nivel;
  final String mayor;
  final String elegido;
  final int liberanMegabytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    return SingleChildScrollView(
      child: Padding(
        key: const Key('mapas_offline_hoja_achicar'),
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Semantics(
              header: true,
              child: Text(
                TextosMapasOffline.achicarTitulo(nivel),
                style: theme.textTheme.headlineSmall,
              ),
            ),
            Text(
              TextosMapasOffline.achicarTexto(
                mayor: mayor,
                elegido: elegido,
                liberanMegabytes: liberanMegabytes,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris),
            ),
            FilledButton(
              key: const Key('mapas_offline_achicar_confirmar'),
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(TextosMapasOffline.achicarAccion(nivel)),
            ),
            OutlinedButton(
              key: const Key('mapas_offline_achicar_cancelar'),
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

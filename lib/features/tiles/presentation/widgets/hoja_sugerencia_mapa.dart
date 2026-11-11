import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/paquete_tiles.dart';
import '../providers/sugerencia_mapa_providers.dart';
import '../textos_mapas_offline.dart';

/// Escucha la sugerencia de mapa de [colportorId] y, cuando llega, abre la hoja «Bajá el mapa de tu
/// zona» (vista 35, 35-10) sobre la pantalla en que esté. No dibuja nada propio.
class SugerenciaMapaZona extends ConsumerStatefulWidget {
  const SugerenciaMapaZona({super.key, required this.colportorId});

  final String colportorId;

  @override
  ConsumerState<SugerenciaMapaZona> createState() => _SugerenciaMapaZonaState();
}

class _SugerenciaMapaZonaState extends ConsumerState<SugerenciaMapaZona> {
  bool _abierta = false;

  Future<void> _abrir() async {
    if (_abierta || !mounted) return;
    _abierta = true;
    final proveedor = sugerenciaMapaProvider(widget.colportorId);
    try {
      if (ref.read(proveedor) == null) return;
      final acepto = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => HojaSugerenciaMapa(colportorId: widget.colportorId),
      );
      if (!mounted) return;
      if (acepto != true) ref.read(proveedor.notifier).ahoraNo();
    } finally {
      _abierta = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sugerenciaMapaProvider(widget.colportorId), (_, nueva) {
      if (nueva != null) unawaited(_abrir());
    });
    return const SizedBox.shrink();
  }
}

/// La hoja «Bajá el mapa de tu zona»: qué mapa, cuánto pesa y por qué se sugiere ahora. «Descargar»
/// arranca la descarga; si falla (sin lugar, por ejemplo) la hoja lo dice y se puede reintentar.
class HojaSugerenciaMapa extends ConsumerStatefulWidget {
  const HojaSugerenciaMapa({super.key, required this.colportorId});

  final String colportorId;

  @override
  ConsumerState<HojaSugerenciaMapa> createState() => _HojaSugerenciaMapaState();
}

class _HojaSugerenciaMapaState extends ConsumerState<HojaSugerenciaMapa> {
  bool _pidiendo = false;

  Future<void> _descargar() async {
    if (_pidiendo) return;
    setState(() => _pidiendo = true);
    var salio = false;
    try {
      salio = await ref.read(sugerenciaMapaProvider(widget.colportorId).notifier).descargar();
    } finally {
      if (mounted) setState(() => _pidiendo = false);
    }
    if (salio && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final sugerencia = ref.watch(sugerenciaMapaProvider(widget.colportorId));
    if (sugerencia == null) return const SizedBox.shrink();
    final paquete = sugerencia.paquete;
    final esZona = paquete.nivel == NivelCobertura.zona;
    final peso = TextosMapasOffline.peso(paquete.tamanoBytes);
    final titulo = esZona ? 'Bajá el mapa de tu zona' : 'Bajá el mapa de tu ciudad';
    final texto = esZona
        ? 'Te asignaron ${sugerencia.zonaNombre ?? 'una zona'}. Estás con Wi-Fi: bajá su mapa '
              '($peso) para usarlo sin señal.'
        : 'Estás con Wi-Fi: bajá el mapa de ${sugerencia.ciudadNombre ?? 'tu ciudad'} ($peso) '
              'para usarlo sin señal.';
    return SingleChildScrollView(
      child: Padding(
        key: const Key('sugerencia_mapa_hoja'),
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Semantics(header: true, child: Text(titulo, style: theme.textTheme.headlineSmall)),
            Text(texto, style: theme.textTheme.bodyMedium?.copyWith(color: colores.gris)),
            if (sugerencia.falla case final falla?)
              Semantics(
                liveRegion: true,
                child: Text(
                  falla.mensaje,
                  key: const Key('sugerencia_mapa_falla'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            FilledButton(
              key: const Key('sugerencia_mapa_descargar'),
              onPressed: _pidiendo ? null : _descargar,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text(TextosMapasOffline.descargar),
            ),
            OutlinedButton(
              key: const Key('sugerencia_mapa_ahora_no'),
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text(TextosMapasOffline.ahoraNo),
            ),
          ],
        ),
      ),
    );
  }
}

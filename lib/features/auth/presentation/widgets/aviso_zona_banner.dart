import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/aviso_zona.dart';

/// El aviso de zona (HU-CAM-006, #251) arriba de la pantalla principal: «Te asignaron la zona
/// `zona` en `campaña`.» o «Ya no tenés zona en `campaña`.», con «Entendido» para cerrarlo.
///
/// Sin artboard propio: se arma con los componentes y la paleta del resto de la app (texto de la
/// HU, tarjeta de superficie con borde suave, ícono y botón de texto). El lector de pantalla lo
/// anuncia al aparecer (región viva, WCAG 4.1.3).
class AvisoZonaBanner extends StatelessWidget {
  const AvisoZonaBanner({super.key, required this.aviso, required this.onCerrar});

  final AvisoZona aviso;

  final VoidCallback onCerrar;

  /// El texto del aviso, el de la HU-CAM-006.
  static String texto(AvisoZona aviso) => switch (aviso) {
    ZonaAsignada(:final zonaNombre, :final campaniaNombre) =>
      'Te asignaron la zona $zonaNombre en $campaniaNombre.',
    ZonaQuitada(:final campaniaNombre) => 'Ya no tenés zona en $campaniaNombre.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final esquema = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: esquema.surfaceContainerHighest,
          border: Border(bottom: BorderSide(color: colores.borde)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 12, 18, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  ExcludeSemantics(
                    child: Icon(Icons.place_outlined, size: 22, color: esquema.primary),
                  ),
                  Expanded(
                    child: Text(
                      texto(aviso),
                      key: Key('aviso_zona_texto_${aviso.inscripcionId}'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: esquema.onSurface),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: Key('aviso_zona_cerrar_${aviso.inscripcionId}'),
                  onPressed: onCerrar,
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los avisos de zona pendientes, uno encima del otro, arriba de la pantalla principal. Con muchos
/// (o con el texto al 200 %) ocupan a lo sumo el 40 % del alto y se desplazan: el contenido de la
/// pestaña nunca queda tapado del todo.
class AvisosZonaPendientes extends StatelessWidget {
  const AvisosZonaPendientes({super.key, required this.avisos, required this.onCerrar});

  final List<AvisoZona> avisos;
  final void Function(AvisoZona aviso) onCerrar;

  @override
  Widget build(BuildContext context) {
    if (avisos.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
      child: ListView(
        key: const Key('avisos_zona'),
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final aviso in avisos)
            AvisoZonaBanner(key: ValueKey(aviso), aviso: aviso, onCerrar: () => onCerrar(aviso)),
        ],
      ),
    );
  }
}

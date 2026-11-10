import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';

/// Lo que dice «Hoy» (vista 20, A06) cuando no se puede leer la jornada guardada, y la pantalla de
/// la cuenta restringida (#472) con el mismo texto.
const textoNoPudimosLeerJornada = 'No pudimos leer tu jornada.';
const textoReintentarLeerJornada =
    'Tocá “Reintentar” para volver a cargarla. Tus datos siguen guardados en este teléfono.';

/// Aviso en línea: error (qué pasó y qué hacer) o información (el bloqueo de jornada activa).
class AvisoJornada extends StatelessWidget {
  const AvisoJornada({super.key, required this.texto, this.esError = false});

  final String texto;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esquema = theme.colorScheme;

    final fondo = esError ? esquema.errorContainer : esquema.surfaceContainerHighest;
    final color = esError ? esquema.onErrorContainer : esquema.onSurface;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(14),
          border: esError ? null : Border.all(color: colores.borde, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              esError ? Icons.error_outline : Icons.info_outline,
              color: esError ? color : esquema.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(texto, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

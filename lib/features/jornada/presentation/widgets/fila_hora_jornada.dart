import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';

/// La hora de inicio (o de fin) como fila tocable: abre la hoja donde se ajusta (A01 del diseño).
/// La comparten «Hoy» y la pantalla de la cuenta restringida (#472).
class FilaHoraJornada extends StatelessWidget {
  const FilaHoraJornada({
    super.key,
    this.sufijoKey = '',
    this.etiqueta = 'HORA DE INICIO',
    required this.hora,
    required this.detalle,
    required this.onTap,
  });

  /// Distingue las keys de la fila de fin (`_fin`) de las de inicio.
  final String sufijoKey;
  final String etiqueta;

  /// "Ahora" o la hora elegida ("14:25").
  final String hora;

  /// La hora actual si es "Ahora", o "hace 10 min".
  final String detalle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esquema = theme.colorScheme;

    return Material(
      color: esquema.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('jornada_ajustar_hora$sufijoKey'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colores.borde),
          ),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      etiqueta,
                      style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
                    ),
                    Text.rich(
                      key: Key('jornada_hora$sufijoKey'),
                      TextSpan(
                        children: [
                          TextSpan(
                            text: hora,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: ' · $detalle'),
                        ],
                      ),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              Text(
                'Cambiar ›',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  // Sin acción se ve apagado, en el gris de los textos sin acción (cumple AA).
                  color: onTap == null ? colores.gris : esquema.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

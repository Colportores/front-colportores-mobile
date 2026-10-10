import 'package:flutter/material.dart';

/// El texto de un botón que está trabajando: círculo girando + [texto] ("Iniciando…",
/// "Finalizando…"). Lo comparten Hoy y "¿A qué hora terminaste?", así el momento de espera dice lo
/// mismo en las dos y el lector de pantalla lee el nombre del botón, no solo "botón".
///
/// El botón que lo lleva está apagado (no admite otro toque mientras trabaja) y Material pinta un
/// botón apagado con texto gris al 38 %, que sobre el azul queda ilegible. Por eso el botón se
/// arma con [estiloDelBoton]: blanco sobre el azul al 85 %, como la vista 21A·04, y el círculo
/// del mismo color que la etiqueta.
class ConEspera extends StatelessWidget {
  const ConEspera(this.texto, {super.key});

  final String texto;

  /// El estilo del `FilledButton` mientras trabaja: etiqueta en `onPrimary` sobre `primary` al
  /// 85 % (se pasa como `style` solo en ese estado; el resto sale del tema).
  static ButtonStyle estiloDelBoton(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      disabledBackgroundColor: esquema.primary.withValues(alpha: .85),
      disabledForegroundColor: esquema.onPrimary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: color,
            backgroundColor: color.withValues(alpha: .35),
          ),
        ),
        Flexible(child: Text(texto)),
      ],
    );
  }
}

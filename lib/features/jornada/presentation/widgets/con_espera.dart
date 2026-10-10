import 'package:flutter/material.dart';

/// El texto de un botón que está trabajando: círculo girando + [texto] ("Iniciando…",
/// "Finalizando…"). Lo comparten Hoy y "¿A qué hora terminaste?", así el momento de espera dice lo
/// mismo en las dos y el lector de pantalla lee el nombre del botón, no solo "botón".
class ConEspera extends StatelessWidget {
  const ConEspera(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 10,
    children: [
      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      Flexible(child: Text(texto)),
    ],
  );
}

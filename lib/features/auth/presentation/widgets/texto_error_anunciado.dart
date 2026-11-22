import 'package:flutter/material.dart';

/// Texto de error de un formulario de acceso que el lector de pantalla anuncia apenas aparece
/// (WCAG 4.1.3, AA): una región viva con su propio nodo de semántica, igual que el aviso de sesión
/// del login.
///
/// [textoKey] va en el `Text`, para que cada pantalla conserve la `Key` que ya usaban sus tests.
/// Sin [style] es el texto en el color de error del tema.
class TextoErrorAnunciado extends StatelessWidget {
  const TextoErrorAnunciado(this.texto, {super.key, this.textoKey, this.style});

  final String texto;
  final Key? textoKey;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Text(
        texto,
        key: textoKey,
        style: style ?? TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

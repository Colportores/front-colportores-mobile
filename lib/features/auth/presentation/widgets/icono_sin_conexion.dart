import 'package:flutter/material.dart';

/// El círculo lleno con una ✕ del aviso «sin conexión» del canvas: 17-A02 en el login (#248) y
/// 12-A08 en la verificación del email (#325). Neutro a propósito: no es un error de la cuenta, así
/// que no lleva el rojo. El aviso que lo usa pinta además su borde con [BordeDiscontinuo] en gris.
///
/// Va fuera del árbol de accesibilidad: el texto del aviso ya dice qué pasa.
class IconoSinConexion extends StatelessWidget {
  const IconoSinConexion({super.key});

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(shape: BoxShape.circle, color: esquema.onSurfaceVariant),
        child: Icon(Icons.close, size: 13, color: esquema.onPrimary),
      ),
    );
  }
}

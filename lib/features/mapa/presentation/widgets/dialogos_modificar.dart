import 'package:flutter/material.dart';

import 'hoja_modificar.dart';
import 'piezas_alta.dart';

/// El aviso de la vista 07·04: «¿Descartar los cambios?». Devuelve `true` si el colportor eligió
/// «Descartar»; `false` con «Seguir editando» o si cerró el aviso de otro modo.
Future<bool> confirmarDescartarCambios(BuildContext context, List<String> cambios) async {
  final descartar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // Con el texto del sistema muy grande el aviso no entra en la pantalla: se desplaza y los dos
      // botones siguen a mano (#324).
      scrollable: true,
      title: const Text(TextosModificar.descartarTitulo),
      content: Text(TextosModificar.descartarCuerpo(cambios)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          child: const Text(TextosModificar.seguirEditando),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: ColoresAlta.rojo,
            minimumSize: const Size(64, 48),
          ),
          child: const Text(TextosModificar.descartar),
        ),
      ],
    ),
  );
  return descartar ?? false;
}

/// Una pregunta del guardado que el colportor tiene que contestar con «Confirmar» o «Cancelar»:
/// reactivar la ubicación, cambiarle la ciudad o moverla más de 100 m. [texto] es el aviso de la HU
/// tal cual. Devuelve `true` si confirmó.
Future<bool> confirmarModificacion(BuildContext context, {required String texto}) async {
  final confirmo = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      content: Text(texto),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          child: const Text(TextosModificar.cancelar),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          child: const Text(TextosModificar.confirmar),
        ),
      ],
    ),
  );
  return confirmo ?? false;
}

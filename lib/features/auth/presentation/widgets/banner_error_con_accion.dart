import 'package:flutter/material.dart';

/// Banner de error genérico con una acción (p. ej. "Reintentar"), para fallas de las que el
/// usuario puede recuperarse sin perder lo que ya hizo — no un error que solo se puede leer.
///
/// Mismos componentes que el banner de error simple (`Text` en color de error) + `FilledButton`,
/// sin diseño propio (decisión de Cristian, issue #90: "Servicio temporalmente no disponible" del
/// registro, HU-AUTH-001, "Edge - fallo intermitente del backend"). Pensado para reusarse en login
/// y recuperación de contraseña cuando sus HU pidan el mismo patrón.
class BannerErrorConAccion extends StatelessWidget {
  const BannerErrorConAccion({
    super.key,
    required this.mensaje,
    required this.textoAccion,
    required this.onAccion,
    this.mensajeKey,
  });

  /// Texto del error. Nunca lleva PII (convenciones §7.5): es el mismo [Failure.mensaje] que ya
  /// pasó por esa regla en el dominio.
  final String mensaje;

  final String textoAccion;

  /// `null` deshabilita el botón — mismo criterio que el resto de los botones de la pantalla
  /// mientras hay un envío en curso (evita el doble *tap*).
  final VoidCallback? onAccion;

  /// `Key` del texto del mensaje, para que la pantalla que lo usa conserve la que ya tenían sus
  /// tests (p. ej. `registro_error_general`) al pasar de `Text` suelto a este widget.
  final Key? mensajeKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          mensaje,
          key: mensajeKey,
          style: TextStyle(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: onAccion, child: Text(textoAccion)),
      ],
    );
  }
}

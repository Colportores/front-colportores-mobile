import 'package:flutter/material.dart';

import 'texto_error_anunciado.dart';

/// Banner de error genérico con una acción (p. ej. "Reintentar"), para fallas de las que el
/// usuario puede recuperarse sin perder lo que ya hizo — no un error que solo se puede leer.
///
/// Mismos componentes que el banner de error simple (`Text` en color de error) + `FilledButton`,
/// sin diseño propio (decisión de Cristian, issue #90: "Servicio temporalmente no disponible" del
/// registro, HU-AUTH-001, "Edge - fallo intermitente del backend"). Lo usan el registro y el login
/// (HU-AUTH-001); queda disponible para la recuperación de contraseña si su HU pide lo mismo.
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

  /// El texto del fallo intermitente del backend (HU-AUTH-001, «Edge - fallo intermitente del
  /// backend»), el mismo en el registro y en el login.
  static const servicioNoDisponible =
      'Servicio temporalmente no disponible, reintentá en unos minutos';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Región viva: el lector de pantalla anuncia el fallo al aparecer.
        TextoErrorAnunciado(mensaje, textoKey: mensajeKey),
        const SizedBox(height: 8),
        FilledButton(onPressed: onAccion, child: Text(textoAccion)),
      ],
    );
  }
}

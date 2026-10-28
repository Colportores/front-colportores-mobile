import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/presentation/widgets/borde_discontinuo.dart';

/// De qué clase es un aviso del respaldo en Drive (los `banner` del canvas, vista 16).
enum ClaseAvisoDrive {
  /// Hay que hacer algo: el permiso se perdió o el intento falló. Rojo, con «!».
  error,

  /// Informa, sin urgencia: «No conectamos tu Drive». Azul oscuro, con «i».
  info,

  /// Falta conexión. Borde de trazos gris, con «✕».
  sinConexion,
}

/// Aviso con marca y borde del color de su clase, y una acción opcional («Reconectar»). Es una
/// región viva: el lector de pantalla lo anuncia cuando aparece.
class AvisoDrive extends StatelessWidget {
  const AvisoDrive({
    super.key,
    required this.clase,
    required this.texto,
    this.accion,
    this.alAccionar,
  }) : assert((accion == null) == (alAccionar == null), 'la acción y su texto van juntos');

  final ClaseAvisoDrive clase;
  final String texto;

  /// Rótulo de la acción (por ejemplo «Reconectar»).
  final String? accion;
  final VoidCallback? alAccionar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final (color, marca) = switch (clase) {
      ClaseAvisoDrive.error => (theme.colorScheme.error, '!'),
      ClaseAvisoDrive.info => (const Color(0xFF2A3A52), 'i'),
      ClaseAvisoDrive.sinConexion => (colores.gris, '✕'),
    };
    final contenido = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    marca,
                    style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
                  ),
                ),
              ),
              Expanded(
                child: Text(texto, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
              ),
            ],
          ),
          if (accion != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('aviso_drive_accion'),
                onPressed: alAccionar,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: theme.colorScheme.primary,
                ),
                child: Text(accion!),
              ),
            ),
        ],
      ),
    );
    return Semantics(
      liveRegion: true,
      container: true,
      child: clase == ClaseAvisoDrive.sinConexion
          ? BordeDiscontinuo(color: color, radio: 14, child: contenido)
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: contenido,
            ),
    );
  }
}

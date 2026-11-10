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

  /// Salió a medias: se hizo lo que se pudo y se dice qué quedó afuera. Ámbar, con «!».
  advertencia,
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
    this.detalle,
  }) : assert(accion != null || alAccionar == null, 'sin texto de acción no hay a qué accionar');

  final ClaseAvisoDrive clase;
  final String texto;

  /// Rótulo de la acción (por ejemplo «Reconectar»).
  final String? accion;

  /// Qué hace la acción. Con [accion] y sin esto, el botón queda apagado (un reintento en curso).
  final VoidCallback? alAccionar;

  /// Una línea de más bajo el texto (por ejemplo, por qué falló el último intento). Al aparecer, el
  /// lector de pantalla la anuncia: el aviso es una región viva.
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final (color, marca) = switch (clase) {
      ClaseAvisoDrive.error => (theme.colorScheme.error, '!'),
      ClaseAvisoDrive.info => (const Color(0xFF2A3A52), 'i'),
      ClaseAvisoDrive.sinConexion => (colores.gris, '✕'),
      ClaseAvisoDrive.advertencia => (const Color(0xFF8A6A12), '!'),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Text(texto, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                    if (detalle != null)
                      Text(
                        detalle!,
                        key: const Key('aviso_drive_detalle'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
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

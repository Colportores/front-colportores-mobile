import 'package:flutter/material.dart';

/// Colores de las vistas 03 y 04 (alta de ubicación) que el tema no cubre: estados del GPS y
/// avisos. Los demás salen de `Theme.of(context)`.
abstract final class ColoresAlta {
  static const verde = Color(0xFF1F6E3A);
  static const verdeFondo = Color(0xFFE3F0E6);
  static const ambar = Color(0xFF7A5A12);
  static const ambarBorde = Color(0xFFA98330);
  static const azul = Color(0xFF13407A);
  static const azulFondo = Color(0xFFE6EEF8);
  static const gris = Color(0xFF4A5A72);
  static const grisBorde = Color(0xFFCFD6E1);
  static const grisFondo = Color(0xFFE3E7EE);
  static const tinta = Color(0xFF2A3A52);
  static const rojo = Color(0xFFA8312A);
  static const fondoMapa = Color(0xFFF6F5F0);
  static const puntoGps = Color(0xFF2F6FD1);
}

/// Un círculo con un glyph adentro: el «!», «✓» o «✕» de los avisos y del chip del GPS.
class InsigniaCirculo extends StatelessWidget {
  const InsigniaCirculo({super.key, required this.color, required this.glyph, this.tamano = 22});

  final Color color;
  final String glyph;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: tamano,
        height: tamano,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          glyph,
          style: TextStyle(
            color: Colors.white,
            fontSize: tamano * .55,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// El cuadro de aviso de las vistas 03 y 04: borde de color, insignia y texto, con acciones
/// opcionales abajo. Se anuncia a los lectores de pantalla.
class AvisoAlta extends StatelessWidget {
  const AvisoAlta({
    super.key,
    required this.color,
    required this.glyph,
    required this.texto,
    this.acciones,
    this.colorInsignia,
  });

  final Color color;

  /// Si no se pasa, la insignia usa [color].
  final Color? colorInsignia;
  final String glyph;
  final String texto;
  final Widget? acciones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InsigniaCirculo(color: colorInsignia ?? color, glyph: glyph),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(texto, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                ),
              ],
            ),
            if (acciones != null) ...[const SizedBox(height: 12), acciones!],
          ],
        ),
      ),
    );
  }
}

/// Botón de texto del color de enlace de la app, con el alto mínimo de un objetivo táctil.
class EnlaceAlta extends StatelessWidget {
  const EnlaceAlta({super.key, required this.texto, required this.alPresionar});

  final String texto;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: alPresionar,
      style: TextButton.styleFrom(
        foregroundColor: ColoresAlta.azul,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(texto),
    );
  }
}

/// El pin de la nueva ubicación: una gota navy con el pico abajo. Con [colocado] en `false` (todavía
/// sin punto) es una gota blanca con borde punteado.
class PinAlta extends StatelessWidget {
  const PinAlta({super.key, this.colocado = true});

  final bool colocado;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Punto de la nueva ubicación',
      child: SizedBox(
        width: 36,
        height: 36 + 8,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Transform.rotate(
              angle: -0.7853981633974483,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colocado ? navy : Colors.white,
                  border: Border.all(color: colocado ? Colors.white : ColoresAlta.gris, width: 3),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x4D000000), blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

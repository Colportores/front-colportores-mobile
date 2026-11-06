import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;

// Las piezas de «Entregar ahora» (vista 27, grupo B). Crecen con el texto (`textScaler` 2.0): nada
// tiene alto fijo salvo el mínimo táctil de 48.

const _borde = Color(0xFFE3E7EE);
const _verdeTinta = Color(0xFF1F6E3A);

/// Una fila de «Qué entregás» (27B·01): se tilda y se destilda. Es de elección **múltiple**: el
/// cuadradito con ✓ del canvas, no la ruedita de las filas de una sola opción.
class FilaDeEntrega extends StatelessWidget {
  const FilaDeEntrega({
    super.key,
    required this.titulo,
    required this.marcada,
    required this.alCambiar,
    this.detalle,
  });

  final String titulo;
  final String? detalle;
  final bool marcada;

  /// `null` mientras se guarda: la fila no responde.
  final VoidCallback? alCambiar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: marcada,
      enabled: alCambiar != null,
      label: [titulo, ?detalle].join('. '),
      onTap: alCambiar,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alCambiar,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: marcada ? const Color(0xFFF2F6FB) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: marcada ? ColoresAgenda.navy : _borde,
                width: marcada ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      if (detalle != null)
                        Text(
                          detalle!,
                          style: const TextStyle(fontSize: 12, color: ColoresAgenda.gris),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  key: const Key('entrega_casilla'),
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: marcada ? ColoresAgenda.navy : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: marcada ? ColoresAgenda.navy : ColoresAgenda.gris,
                      width: 1.5,
                    ),
                  ),
                  child: marcada ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El cartel grande de 27B·03: un círculo verde con la estrella, el título y lo que pasó.
class CartelDeVentaCompleta extends StatelessWidget {
  const CartelDeVentaCompleta({super.key, required this.titulo, required this.detalle});

  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: _verdeTinta, shape: BoxShape.circle),
            child: const ExcludeSemantics(
              child: Text('★', style: TextStyle(fontSize: 32, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 18),
          Semantics(
            liveRegion: true,
            child: Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'SourceSerif4',
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.4, color: ColoresAgenda.tinta),
          ),
        ],
      ),
    );
  }
}

/// Una línea «Entregado — todo» / «Saldo — $ 2.500» de 27B·04.
class RenglonDeResumen extends StatelessWidget {
  const RenglonDeResumen({
    super.key,
    required this.rotulo,
    required this.valor,
    this.cifra = false,
  });

  final String rotulo;
  final String valor;

  /// El valor va en la letra de las cifras (el saldo).
  final bool cifra;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEF0F3))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(rotulo, style: const TextStyle(fontSize: 14, color: ColoresAgenda.gris)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: cifra ? FontWeight.w600 : FontWeight.w500,
                fontFamily: cifra ? 'JetBrainsMono' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

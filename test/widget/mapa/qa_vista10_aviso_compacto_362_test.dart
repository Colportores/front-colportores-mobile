// QA del PR #381 (#362; vista 10 «Posibles duplicados», HU-UBI-006): el contraste del aviso rojo de
// una línea (`_FallaCompacta`), que la matriz de `qa_vista10_seguimiento_340_test.dart` no mide (sus
// guías de accesibilidad dejan el contraste aparte por las fuentes reales). Se miden los colores que
// pinta la línea (fondo blanco, borde y glifo rojos, cuenta en tinta, «Reintentar» en azul) contra
// su fondo: texto ≥ 4,5:1 (WCAG 1.4.3) y borde/glifo ≥ 3:1 (WCAG 1.4.11).
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart'
    show ColoresAlta;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista10_arnes.dart' show contraste208;

void main() {
  const fondo = Colors.white;

  group('Aviso rojo de una línea (#362): contraste de lo que pinta', () {
    test('la cuenta («2 no se pudieron unir») en tinta sobre el blanco: texto ≥ 4,5:1', () {
      expect(contraste208(ColoresAlta.tinta, fondo), greaterThanOrEqualTo(4.5));
    });

    test('«Reintentar» en azul sobre el blanco: texto ≥ 4,5:1', () {
      expect(contraste208(ColoresAlta.azul, fondo), greaterThanOrEqualTo(4.5));
    });

    test('el borde y el glifo «!» en rojo sobre el blanco: ≥ 3:1', () {
      expect(contraste208(ColoresAlta.rojo, fondo), greaterThanOrEqualTo(3));
    });

    test('el glifo blanco «!» sobre el círculo rojo: ≥ 3:1', () {
      expect(contraste208(Colors.white, ColoresAlta.rojo), greaterThanOrEqualTo(3));
    });
  });
}

// QA r2 de #143 (PR #488): el nombre de una persona en las filas de «Clientes» (activa) y de «Mostrar
// bajas» no se corta con «…» cuando el texto pasa de 1,5×, y a la escala de siempre sigue acotado a
// tres renglones. Matriz de tamaños × escalas × las dos filas, con las fuentes reales del proyecto.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';
import 'qa_vista32d_baja_143_arnes.dart';

const _nombres = <(String, String, String)>[
  ('compuesto', 'Maximiliano Alejandro', 'Fernández de la Peña'),
  (
    'larguisimo',
    'Maximiliano Maximiliano Maximiliano Maximiliano',
    'Fernández de la Peña de Todos',
  ),
  (
    'una palabra larga',
    'Maximilianomaximilianomaximilianomaximiliano',
    'Hernándezdelapeñadetodoslossantos',
  ),
  ('corto', 'Ana', 'Paz'),
];
const _tamanosQa = [Size(320, 568), Size(360, 640), Size(412, 915)];
// Hasta 2,0× (WCAG 1.4.4). A 3,0× la cabecera fija de la página ya ocupa casi todo el teléfono chico
// (preexistente, no es del cambio): solo se mira a 412×915.
const _escalasQa = [1.0, 1.5, 1.51, 2.0];

final _mostrar = find.widgetWithText(SwitchListTile, 'Mostrar bajas');
final _reactivar = find.widgetWithText(TextButton, 'Reactivar');

Future<void> _montar(
  WidgetTester tester, {
  required bool baja,
  required String nombre,
  required String apellido,
  required Size tamano,
  required double escala,
}) async {
  final repo = PersonaRepositorioFalso()
    ..sembrar([
      if (baja)
        clienteDeBajaDePersonas('p2', nombre, apellido: apellido)
      else
        clienteDePersonas('p1', nombre, apellido: apellido),
    ]);
  await cargarFuentes(tester);
  await montarClientes(
    tester,
    repo: repo,
    escala: escala,
    tamano: tamano,
    otrosOverrides: extrasBajas(saldos: baja ? {'p2': 120000} : null),
  );
  if (baja) {
    await verEnPantalla(tester, _mostrar);
    await tester.tap(_mostrar);
    await asentar(tester);
  }
}

Text _textoDelNombre(WidgetTester tester, String completo) =>
    tester.widget<Text>(find.text(completo).first);

void main() {
  group('QA #143 r2 · nombre sin recorte (PR #488)', () {
    for (final baja in [false, true]) {
      for (final (rotulo, nombre, apellido) in _nombres) {
        for (final tamano in _tamanosQa) {
          for (final escala in [..._escalasQa, if (tamano.height > 900) 3.0]) {
            testWidgets(
              '${baja ? 'fila de baja' : 'fila activa'} · $rotulo · ${tamano.width.toInt()}×'
              '${tamano.height.toInt()} · texto $escala×',
              (tester) async {
                await _montar(
                  tester,
                  baja: baja,
                  nombre: nombre,
                  apellido: apellido,
                  tamano: tamano,
                  escala: escala,
                );
                expect(tester.takeException(), isNull, reason: 'desborde de la fila');
                if (rotulo == 'compuesto' && tamano.width == 360 && (escala == 1 || escala == 2)) {
                  await capturar(tester, 'sinrecorte_${baja ? 'baja' : 'activa'}_x$escala');
                }

                final completo = '$nombre $apellido';
                final texto = _textoDelNombre(tester, completo);
                if (escala > 1.5) {
                  expect(texto.maxLines, isNull, reason: 'a más de 1,5× no hay tope de renglones');
                  expect(
                    texto.overflow,
                    isNot(TextOverflow.ellipsis),
                    reason: 'a más de 1,5× no lleva «…»',
                  );
                } else {
                  expect(texto.maxLines, 3);
                  expect(texto.overflow, TextOverflow.ellipsis);
                }
                if (escala > 1.5) sinTextoCortado(tester);

                // El nombre entero está dentro del ancho de la pantalla (ni recorte lateral).
                final r = tester.getRect(find.text(completo).first);
                expect(r.left, greaterThanOrEqualTo(-0.5));
                expect(r.right, lessThanOrEqualTo(tamano.width + 0.5));

                if (baja) {
                  await verEnPantalla(tester, _reactivar);
                  dentroDeLaPantalla(tester, _reactivar, rotulo: 'Reactivar');
                  expect(tester.getSize(_reactivar.first).height, greaterThanOrEqualTo(48));
                }
              },
            );
          }
        }
      }
    }

    for (final baja in [false, true]) {
      testWidgets(
        '${baja ? 'fila de baja' : 'fila activa'} · guías de accesibilidad con nombre largo a 360×640 y 2,0×',
        (tester) async {
          await _montar(
            tester,
            baja: baja,
            nombre: 'Maximiliano Alejandro',
            apellido: 'Fernández de la Peña',
            tamano: const Size(360, 640),
            escala: 2,
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        },
      );

      testWidgets(
        '${baja ? 'fila de baja' : 'fila activa'} · el lector lee el nombre entero a 2,0×',
        (tester) async {
          final handle = tester.ensureSemantics();
          await _montar(
            tester,
            baja: baja,
            nombre: 'Maximiliano Alejandro',
            apellido: 'Fernández de la Peña',
            tamano: const Size(360, 640),
            escala: 2,
          );
          expect(
            find.bySemanticsLabel(RegExp('Maximiliano Alejandro Fernández de la Peña')),
            findsWidgets,
          );
          handle.dispose();
        },
      );
    }
  });
}

// QA de #561 (vista 26 «Precios», HU-CAT-006): la etiqueta de cada producto sale de su categoría y
// «◆ Bonificable» va aparte del sí/no. Casos que el PR no cubre: las marcas sueltas (P2) contra la
// categoría, la pestaña por categoría sin la marca `es_misionero`, la matriz de tamaños y escalas con
// fuentes reales, las guías de accesibilidad con todas las etiquetas a la vista, el contraste de cada
// pastilla, el lector de pantalla y las capturas (solo con `--dart-define=QA_CAPTURAS=true`).
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/presentation/widgets/piezas_precios.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/precios_falsos.dart';
import '../../helpers/qa_precios_561_arnes.dart';

Finder _enLaFila(String nombre, String etiqueta) => find.descendant(
  of: find.ancestor(of: find.text(nombre), matching: find.byType(Row)).first,
  matching: find.text(etiqueta),
);

void main() {
  setUpAll(cargarFuentes561);

  group('la categoría manda sobre las marcas sueltas (P2)', () {
    testWidgets('Libros: un bonificable con es_misionero queda en Libros con una sola ◆', (
      tester,
    ) async {
      await montar561(tester, Entorno561());
      await irA561(tester, 'libros');
      await hasta561(tester, find.text('Bonificable con marca misionera'));
      expect(_enLaFila('Bonificable con marca misionera', '◆ Bonificable'), findsOneWidget);
      expect(_enLaFila('Bonificable con marca misionera', '✦ Misionero'), findsNothing);
    });

    testWidgets(
      'Libros: un espiritual con es_misionero lleva ✝ Espiritual y no está en Misioneros',
      (tester) async {
        await montar561(tester, Entorno561());
        await irA561(tester, 'libros');
        await hasta561(tester, find.text('Espiritual con marca misionera'));
        expect(_enLaFila('Espiritual con marca misionera', '✝ Espiritual'), findsOneWidget);
        expect(_enLaFila('Espiritual con marca misionera', '✦ Misionero'), findsNothing);
        await irA561(tester, 'misioneros');
        expect(find.text('Espiritual con marca misionera'), findsNothing);
        expect(find.text('Bonificable con marca misionera'), findsNothing);
      },
    );

    testWidgets('Misioneros: la categoría alcanza, sin la marca es_misionero', (tester) async {
      await montar561(tester, Entorno561());
      await irA561(tester, 'misioneros');
      expect(find.text('Misionero sin marca'), findsOneWidget);
      expect(_enLaFila('Misionero sin marca', '✦ Misionero'), findsOneWidget);
      expect(_enLaFila('Misionero bonificable', '✦ Misionero'), findsOneWidget);
      expect(_enLaFila('Misionero bonificable', '◆ Bonificable'), findsOneWidget);
    });

    testWidgets('Revistas: una revista bonificable lleva Revista y ◆ Bonificable', (tester) async {
      await montar561(tester, Entorno561());
      await irA561(tester, 'revistas');
      expect(_enLaFila('Revista bonificable', 'Revista'), findsOneWidget);
      expect(_enLaFila('Revista bonificable', '◆ Bonificable'), findsOneWidget);
      expect(_enLaFila('Revista Vida y Salud', '◆ Bonificable'), findsNothing);
    });

    testWidgets(
      'no se ofrece el material, lo sin categoría ni lo dado de baja, aunque cuente para la beca',
      (tester) async {
        await montar561(tester, Entorno561());
        for (final pestana in ['libros', 'misioneros', 'revistas']) {
          await irA561(tester, pestana);
          for (final nombre in [
            'Material bonificable',
            'Sin categoría bonificable',
            'Espiritual dado de baja',
          ]) {
            for (var i = 0; i < 30; i++) {
              await tester.drag(find.byKey(const Key('precios_scroll')), const Offset(0, -400));
              await tester.pump();
            }
            expect(find.text(nombre), findsNothing, reason: '$nombre en $pestana');
          }
        }
      },
    );
  });

  group('Pestaña vacía por categoría', () {
    testWidgets('sin ninguna revista, la pestaña Revistas explica y no queda en blanco', (
      tester,
    ) async {
      final catalogo = catalogoPorCategorias();
      final sinRevistas = CatalogoLocal(
        productos: [
          for (final p in catalogo.productos)
            if (p.categoria != CategoriaDeProducto.revistas) p,
        ],
        generales: catalogo.generales,
      );
      await montar561(tester, Entorno561(repo: ConsultaDePreciosFalsa(sinRevistas)));
      await irA561(tester, 'revistas');
      expect(
        find.text('Si esperabas verlos, puede que no tengan precio en esta ciudad.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'todos los productos sin categoría (recién actualizada la app): Libros no queda en blanco',
      (tester) async {
        const sinCategoria = CatalogoLocal(
          productos: [
            ProductoDelCatalogo(
              id: 'a',
              nombre: 'Libro viejo',
              categoria: CategoriaDeProducto.otra,
            ),
          ],
          generales: [
            PrecioDelCatalogo(id: 'g', productoId: 'a', centavos: 1000, validoDesde: '2026-01-01'),
          ],
        );
        await montar561(tester, Entorno561(repo: ConsultaDePreciosFalsa(sinCategoria)));
        await irA561(tester, 'libros');
        expect(find.text('Libro viejo'), findsNothing);
        expect(
          find.text('Si esperabas verlos, puede que no tengan precio en esta ciudad.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Lector de pantalla', () {
    testWidgets('dice la categoría y, aparte, que es bonificable, una sola vez', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar561(tester, Entorno561());
      await irA561(tester, 'libros');
      await hasta561(tester, find.text('Salud y Hogar'));
      expect(
        find.bySemanticsLabel(RegExp(r'^Salud y Hogar, código SH-12, bonificable, \$ 1\.000$')),
        findsOneWidget,
      );
      await hasta561(tester, find.text('El Deseado de todas las gentes'));
      expect(
        find.bySemanticsLabel(
          RegExp(r'^El Deseado de todas las gentes, código DG-01, espiritual, \$ 1\.000$'),
        ),
        findsOneWidget,
      );
      await irA561(tester, 'misioneros');
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Misionero bonificable, misionero, bonificable, \$ 1\.000$'),
        ),
        findsOneWidget,
      );
      await irA561(tester, 'revistas');
      expect(
        find.bySemanticsLabel(RegExp(r'^Revista bonificable, revista, bonificable, \$ 1\.000$')),
        findsOneWidget,
      );
      semantica.dispose();
    });
  });

  group('Contraste de cada pastilla (WCAG 1.4.3, texto de 11 px: 4,5:1)', () {
    final pares = <String, (Color, Color)>{
      '◆ Bonificable': (ColoresPrecios.azul, ColoresPrecios.azulFondo),
      '✦ Misionero': (ColoresPrecios.verdeTinta, ColoresPrecios.verdeFondo),
      'Revista': (ColoresPrecios.ambarTinta, ColoresPrecios.ambarFondo),
      '✝ Espiritual': (ColoresPrecios.espiritualTinta, ColoresPrecios.espiritualFondo),
    };
    for (final MapEntry(key: nombre, value: (tinta, fondo)) in pares.entries) {
      test(nombre, () {
        expect(contraste561(tinta, fondo), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('Matriz de tamaños y escalas (fuentes reales)', () {
    for (final tamano in [telefonoChico561, telefonoGrande561]) {
      for (final escala in [1.0, 2.0]) {
        for (final pestana in ['libros', 'misioneros', 'revistas']) {
          testWidgets(
            '${tamano.width.toInt()}x${tamano.height.toInt()} · ×$escala · $pestana: sin overflow ni texto fuera',
            (tester) async {
              await montar561(tester, Entorno561(), tamano: tamano, escala: escala);
              await irA561(tester, pestana);
              expect(tester.takeException(), isNull);
              // Se recorre toda la lista: las filas se arman a medida que se ven.
              for (var i = 0; i < 12; i++) {
                expectSinTextoFueraDeLosCostados561(tester, tamano);
                await tester.drag(find.byKey(const Key('precios_scroll')), const Offset(0, -350));
                await tester.pump();
                expect(tester.takeException(), isNull);
              }
              expectSinTextoFueraDeLosCostados561(tester, tamano);
            },
          );
        }
      }
    }
  });

  group('Guías de accesibilidad con todas las etiquetas a la vista', () {
    for (final tamano in [telefonoChico561, telefonoGrande561]) {
      for (final pestana in ['libros', 'misioneros', 'revistas']) {
        testWidgets('${tamano.width.toInt()}x${tamano.height.toInt()} · $pestana', (tester) async {
          final semantica = tester.ensureSemantics();
          await montar561(tester, Entorno561(), tamano: tamano);
          await irA561(tester, pestana);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }

    testWidgets('texto al 200 % en 360x640 · libros: tap targets y etiquetas', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar561(tester, Entorno561(), tamano: telefonoChico561, escala: 2);
      await irA561(tester, 'libros');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantica.dispose();
    });
  });

  group('Capturas (solo con QA_CAPTURAS=true)', () {
    for (final tamano in [telefonoChico561, telefonoGrande561]) {
      for (final escala in [1.0, 2.0]) {
        for (final pestana in ['libros', 'misioneros', 'revistas']) {
          testWidgets(
            '${tamano.width.toInt()}x${tamano.height.toInt()} ×$escala $pestana',
            (tester) async {
              await montar561(tester, Entorno561(), tamano: tamano, escala: escala);
              await irA561(tester, pestana);
              await capturar561(tester, '${tamano.width.toInt()}_x${escala}_$pestana');
              await tester.drag(find.byKey(const Key('precios_scroll')), const Offset(0, -450));
              await tester.pump();
              await capturar561(tester, '${tamano.width.toInt()}_x${escala}_${pestana}_2');
            },
            skip: !conCapturas561,
          );
        }
      }
    }
  });
}

// QA del Historial de la hoja de la casa (vista 39, C·03 y C·04, #446, PR #677), tercera ronda: lo que
// trajo `e0669f7d` (decisiones del 10/11). La tercera línea del cobro con «Cuota n de m» (C·03) y el
// detalle de una venta como «Colección de N libros · $ total» con una fila «Libro» por renglón (C·04),
// en 360×640 y 412×915 con letra al 100 % y al 200 %: sin desbordar, sin cortar lo que dice qué cubrió
// el cobro, con su etiqueta para el lector y con las guías de toque.
//
// Lo que documenta un hallazgo va con `skip` salvo que se corra con `--dart-define=QA_HALLAZGOS=true`.
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart'
    show MedioCobranza;
import 'package:colportores_mobile/features/cobranzas/domain/services/reparto_de_cuotas.dart'
    show CuotasDeUnCobro;
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart'
    show LineaDeFicha;
import 'package:colportores_mobile/features/mapa/domain/services/historial_de_la_casa.dart'
    show FiltroDeLaCasa;
import 'package:colportores_mobile/features/mapa/presentation/textos_baja_persona.dart'
    show FormatoBajaPersona;
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_detalle_de_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_historial_de_la_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_446_arnes.dart';

const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

CobroDeLaCasa _cobro(String id, CuotasDeUnCobro? cuotas, {String? talonario = '0038'}) =>
    CobroDeLaCasa(
      id: id,
      fecha: fecha446(10, 25, 14, 20),
      montoCentavos: 60000,
      medio: MedioCobranza.efectivo,
      ventaId: 'ven-1',
      numeroTalonario: talonario,
      persona: pedro446,
      cuotas: cuotas,
    );

/// Cada forma de la tercera línea del cobro, con lo que debe decir.
final _variantes = <(String, CuotasDeUnCobro, String)>[
  ('completa', const CuotasDeUnCobro(deTotal: 2, completas: [1]), 'Cuota 1 de 2'),
  ('dos', const CuotasDeUnCobro(deTotal: 3, completas: [1, 2]), 'Cuotas 1 y 2 de 3'),
  ('tres', const CuotasDeUnCobro(deTotal: 4, completas: [1, 2, 3]), 'Cuotas 1 a 3 de 4'),
  ('parte', const CuotasDeUnCobro(deTotal: 3, aMedias: 2), 'Parte de la cuota 2 de 3'),
  (
    'completaYParte',
    const CuotasDeUnCobro(deTotal: 3, completas: [1], aMedias: 2),
    'Cuota 1 y parte de la 2 de 3',
  ),
  (
    'doce',
    const CuotasDeUnCobro(deTotal: 12, completas: [10, 11], aMedias: 12),
    'Cuotas 10 y 11 y parte de la 12 de 12',
  ),
];

final _libros16 = VentaDeLaCasa(
  id: 'ven-16',
  fecha: fecha446(10, 12, 14),
  numeroTalonario: '0099',
  montoCentavos: 1234500,
  pagadoCentavos: 300000,
  lineas: const [
    LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 3),
    LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1),
    LineaDeFicha(nombre: 'El Gran Conflicto de los Siglos: edición ilustrada 😀', cantidad: 12),
  ],
  persona: pedro446,
  espacioPersonaId: 'ep-pedro',
);

void main() {
  Finder fila(String id) => find.byKey(ClavesHistorialDeLaCasa.fila(id));

  group('la tercera línea del cobro (C·03): cada forma × tamaño × letra', () {
    for (final tamano in const [t360x640, t412x915]) {
      for (final escala in const [1.0, 2.0]) {
        for (final (nombre, cuotas, texto) in _variantes) {
          testWidgets(
            'dado el cobro «$texto» a ${tamano.width.toInt()}×${tamano.height.toInt()} con letra ×$escala, '
            'se lee entero y sin desbordar',
            (tester) async {
              await cargarFuentes205(tester);
              await montarHoja446(
                tester,
                eventos: [_cobro('cob-x', cuotas), venta446],
                tamano: tamano,
                escala: escala,
              );
              await tester.ensureVisible(fila('cob-x'));
              await tester.pump();
              await capturar446(tester, 'cuotas_${nombre}_${sufijo446(tamano, escala)}');

              expect(tester.takeException(), isNull);
              expect(find.text(texto), findsOneWidget);
              expect(find.text('Venta 0038'), findsNothing, reason: 'con plan no repite la venta');
              expect(
                textosCortados446(tester).where((t) => t.contains('uota')),
                isEmpty,
                reason: 'lo que cubrió el cobro no se corta con «…»',
              );
            },
          );
        }
      }
    }
  });

  group('la fila del cobro con cuotas, para el lector y para el toque', () {
    testWidgets('dado el cobro con plan, el lector lee antetítulo, título y cuotas de una vez', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarHoja446(
        tester,
        eventos: [
          _cobro('cob-x', const CuotasDeUnCobro(deTotal: 2, completas: [1])),
        ],
      );
      final etiqueta = tester.getSemantics(fila('cob-x')).label;

      expect(etiqueta, contains('HOY 14:20 · COBRO'));
      expect(etiqueta, contains('en efectivo · Pedro'));
      expect(etiqueta, contains('Cuota 1 de 2'));
      expect(etiqueta, isNot(contains('Venta 0038')));
      semantica.dispose();
    });

    testWidgets('dado un cobro con plan pero sin talonario, igual dice la cuota', (tester) async {
      await montarHoja446(
        tester,
        eventos: [
          _cobro('cob-x', const CuotasDeUnCobro(deTotal: 2, completas: [1]), talonario: null),
        ],
      );

      expect(find.text('Cuota 1 de 2'), findsOneWidget);
    });

    testWidgets(
      'dado un cobro sin plan ni talonario, la fila no inventa una tercera línea (y no desborda)',
      (tester) async {
        await montarHoja446(tester, eventos: [_cobro('cob-x', null, talonario: null)]);

        expect(tester.takeException(), isNull);
        expect(find.textContaining('uota'), findsNothing);
        expect(find.textContaining('Venta 0'), findsNothing);
      },
    );

    testWidgets('dado el filtro «Cobros», cada cobro conserva su línea de cuotas', (tester) async {
      await montarHoja446(
        tester,
        eventos: [
          _cobro('cob-1', const CuotasDeUnCobro(deTotal: 2, completas: [1])),
          _cobro('cob-2', const CuotasDeUnCobro(deTotal: 3, aMedias: 2)),
          _cobro('cob-3', null),
          venta446,
        ],
      );
      await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.cobros)));
      await asentar446(tester);

      expect(find.text('Cuota 1 de 2'), findsOneWidget);
      expect(find.text('Parte de la cuota 2 de 3'), findsOneWidget);
      expect(find.text('Venta 0038'), findsOneWidget);
    });

    for (final tamano in const [t360x640, t412x915]) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets(
          'dado un cobro de cada forma a ${tamano.width.toInt()}×${tamano.height.toInt()} con letra '
          '×$escala, cumple las guías de toque y de etiqueta',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await montarHoja446(
              tester,
              eventos: [for (final (i, v) in _variantes.indexed) _cobro('cob-$i', v.$2), venta446],
              tamano: tamano,
              escala: escala,
            );

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            semantica.dispose();
          },
        );
      }

      testWidgets('dado un cobro de cada forma a ${tamano.width.toInt()}×${tamano.height.toInt()}, '
          'el texto cumple el contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        await montarHoja446(
          tester,
          eventos: [for (final (i, v) in _variantes.indexed) _cobro('cob-$i', v.$2), venta446],
          tamano: tamano,
        );
        await tester.pump(const Duration(milliseconds: 400));

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  });

  group(
    'el detalle de una venta (C·04): «Colección de N libros · total» y una fila «Libro» por renglón',
    () {
      for (final tamano in const [t360x640, t412x915]) {
        for (final escala in const [1.0, 2.0]) {
          testWidgets(
            'dado una venta de tres renglones (16 libros) a ${tamano.width.toInt()}×${tamano.height.toInt()} '
            'con letra ×$escala, se lee entera, en orden y sin desbordar',
            (tester) async {
              await cargarFuentes205(tester);
              await montarHoja446(tester, eventos: [_libros16], tamano: tamano, escala: escala);
              await tocarFila446(tester, 'ven-16');
              await capturar446(tester, 'detalle16_${sufijo446(tamano, escala)}');

              expect(tester.takeException(), isNull);
              expect(find.text('Colección de 16 libros'), findsOneWidget);
              expect(find.text('Libro'), findsNWidgets(3));
              expect(find.text('Salud y Hogar × 3'), findsOneWidget);
              expect(find.text('Nuestros Hijos'), findsOneWidget);
              expect(
                find.descendant(
                  of: find.byKey(ClavesDetalleDeVisita.hoja),
                  matching: find.text('El Gran Conflicto de los Siglos: edición ilustrada 😀 × 12'),
                ),
                findsOneWidget,
              );
              expect(find.text('Total'), findsNothing);
              // El orden de arriba abajo: colección, los tres libros, pagado, saldo.
              final y = <String, double>{};
              for (final t in ['Colección de 16 libros', 'Pagado', 'Saldo']) {
                y[t] = tester.getTopLeft(find.text(t)).dy;
              }
              final libros = tester.widgetList<Text>(find.text('Libro')).length;
              expect(libros, 3);
              expect(
                y['Colección de 16 libros']!,
                lessThan(tester.getTopLeft(find.text('Libro').first).dy),
              );
              expect(tester.getTopLeft(find.text('Libro').last).dy, lessThan(y['Pagado']!));
              expect(y['Pagado']!, lessThan(y['Saldo']!));
              // El total de la venta va en la fila de la colección: entre ella y el primer «Libro».
              final total = find.descendant(
                of: find.byKey(ClavesDetalleDeVisita.hoja),
                matching: find.text(FormatoBajaPersona.monto(1234500)),
              );
              expect(total, findsOneWidget);
              final yTotal = tester.getTopLeft(total).dy;
              expect(yTotal, greaterThanOrEqualTo(y['Colección de 16 libros']! - 1));
              expect(yTotal, lessThan(tester.getTopLeft(find.text('Libro').first).dy));
              // «Ver la venta» y «Cerrar» siguen al alcance.
              await tester.ensureVisible(find.byKey(ClavesDetalleDeVisita.cerrar));
              await tester.ensureVisible(find.byKey(ClavesDetalleDeVisita.verLaVenta));
              expect(tester.takeException(), isNull);
            },
          );

          testWidgets(
            'dado el detalle de la venta de 16 libros a ${tamano.width.toInt()}×${tamano.height.toInt()} con '
            'letra ×$escala, cumple las guías de toque, de etiqueta',
            (tester) async {
              final semantica = tester.ensureSemantics();
              await montarHoja446(tester, eventos: [_libros16], tamano: tamano, escala: escala);
              await tocarFila446(tester, 'ven-16');

              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              semantica.dispose();
            },
          );
        }

        testWidgets(
          'dado el detalle de la venta de 16 libros a ${tamano.width.toInt()}×${tamano.height.toInt()}, '
          'el texto cumple el contraste',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await montarHoja446(tester, eventos: [_libros16], tamano: tamano);
            await tocarFila446(tester, 'ven-16');
            await tester.pump(const Duration(milliseconds: 400));

            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          },
        );
      }

      testWidgets('dado un solo libro de un ejemplar, dice «libro» en singular y sin « × 1»', (
        tester,
      ) async {
        await montarHoja446(tester);
        await tocarFila446(tester, 'ven-1');

        expect(find.text('Colección de 1 libro'), findsOneWidget);
        expect(find.text('Salud y Hogar'), findsWidgets);
        expect(find.text('Salud y Hogar × 1'), findsNothing);
        expect(find.text('Colección de 1 libros'), findsNothing);
      });

      testWidgets(
        'dado el detalle de un cobro, no se muestra «Colección» (el detalle de la venta es de la venta)',
        (tester) async {
          // Un cobro sin destino no abre detalle: la fila no responde al toque.
          await montarHoja446(tester);
          await tester.ensureVisible(fila('cob-1'));
          await tester.tap(fila('cob-1'));
          await asentar446(tester);

          expect(find.byKey(ClavesDetalleDeVisita.hoja), findsNothing);
          expect(find.textContaining('Colección'), findsNothing);
        },
      );

      testWidgets(
        'dado una venta sin renglones, el detalle no dice «Colección de 0 libros»',
        (tester) async {
          await montarHoja446(
            tester,
            eventos: [
              VentaDeLaCasa(
                id: 'v-raro',
                fecha: fecha446(10, 20, 10),
                numeroTalonario: '0001',
                montoCentavos: 5000,
                pagadoCentavos: 0,
                lineas: const [],
              ),
            ],
          );
          await tocarFila446(tester, 'v-raro');

          // La fila de la lista dice «Venta» a secas; el detalle no debería contradecirla con «0 libros».
          expect(find.textContaining('0 libros'), findsNothing);
        },
        // skip: QA #446: una venta sin renglones (dato roto, no alcanzable desde la app) dice «Colección de
        // 0 libros» en el detalle, y la fila de la lista dice «Venta» (menor).
        skip: !_conHallazgos,
      );
    },
  );
}

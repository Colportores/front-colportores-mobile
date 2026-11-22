// QA de «la cuota que toca» en la hoja de la casa (vista 39, C·01 «Tocar una casa: resumen» y C·02 «Hoja
// arriba · Personas», HU-COB-005, #591, PR #634): el texto literal del issue y del canvas, los estados de
// la línea en la matriz de tamaños (360×640, 412×915) y escalas de texto (1,0 y 2,0), y el lector de pantalla.
//
// Con fuentes reales (sin ellas `flutter_test` pinta cajas Ahem y las medidas mienten). Las guías de
// accesibilidad van en `qa_vista39_cuota_591_guias_test.dart` (con la fuente de prueba).
// Capturas: `--dart-define=QA_CAPTURAS=true` → `.dart_tool/qa_capturas/591_*.png` (nunca se commitean).
import 'dart:math' as math;

import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart'
    show ColoresAlta;
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/qa_vista39_591_arnes.dart';

const _tamanos = [t360x640, t412x915];
const _escalas = [1.0, 2.0];

/// La línea de una fila: «Debe $ 1.200 · cuota sáb 24/10» (el espacio tras el «$» puede ser fino).
Finder _linea(String monto, String resto) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      w.data != null &&
      RegExp('^Debe \\\$\\s${RegExp.escape(monto)} · $resto\$').hasMatch(w.data!),
  description: 'línea «Debe \$ $monto · $resto»',
);

Finder get _soloDebe => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && RegExp(r'^Debe \$\s[\d.,]+$').hasMatch(w.data!),
);

Finder get _cuotaVencida => find.byKey(ClavesHojaCasa.cuotaVencida);

double _luz(Color c) {
  double canal(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
}

double _contraste(Color a, Color b) {
  final la = _luz(a);
  final lb = _luz(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('Texto literal del issue y del canvas', () {
    for (final arriba in [false, true]) {
      final vista = arriba ? 'C·02 arriba' : 'C·01 resumen';

      testWidgets('$vista · «Debe \$ 1.200 · cuota sáb 24/10» (canvas, con la cuota por venir)', (
        tester,
      ) async {
        await cargarFuentes205(tester);
        await montarHoja445(
          tester,
          arriba: arriba,
          contexto: ContextoDeLaCasa(
            espacioId: 'esp-1',
            personas: [pedroGomez],
            saldosCentavos: const {'p-pedro': 120000},
            // 24/10/2026 es sábado; «hoy» de la hoja es el 06/10.
            proximaCuotaDe: {'p-pedro': DateTime(2026, 10, 24, 12, 30)},
          ),
        );
        await asentar445(tester);

        expect(_linea('1.200', 'cuota sáb 24/10'), findsOneWidget);
        expect(_cuotaVencida, findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        '$vista · «Debe \$ 1.200 · cuota vencida el 04/10» (issue, con la cuota vencida)',
        (tester) async {
          await cargarFuentes205(tester);
          await montarHoja445(
            tester,
            arriba: arriba,
            contexto: ContextoDeLaCasa(
              espacioId: 'esp-1',
              personas: [pedroGomez],
              saldosCentavos: const {'p-pedro': 120000},
              proximaCuotaDe: {'p-pedro': DateTime(2026, 10, 4, 12, 30)},
            ),
          );
          await asentar445(tester);

          expect(_linea('1.200', 'cuota vencida el 04/10'), findsOneWidget);
          expect(_cuotaVencida, findsOneWidget);
        },
      );
    }
  });

  group('Matriz de estados × tamaños × escalas (sin overflow, contenido alcanzable)', () {
    for (final arriba in [false, true]) {
      for (final estado in Estado591.values) {
        for (final tamano in _tamanos) {
          for (final escala in _escalas) {
            final vista = arriba ? 'C02' : 'C01';
            testWidgets('$vista · ${estado.name} · ${sufijo445(tamano, escala)}', (tester) async {
              await cargarFuentes205(tester);
              await llegarA591(tester, estado, tamano: tamano, escala: escala, arriba: arriba);
              await asentar445(tester);

              expect(
                tester.takeException(),
                isNull,
                reason: 'overflow o excepción en ${estado.name}',
              );
              await capturar591(tester, '${vista}_${estado.name}_${sufijo445(tamano, escala)}');

              final proxima = corto591(dia591(4));
              final vencida = dm591(dia591(-2));
              switch (estado) {
                case Estado591.proxima:
                  expect(_linea('1.200', 'cuota $proxima'), findsOneWidget);
                  expect(_cuotaVencida, findsNothing);
                case Estado591.vencida:
                  expect(_linea('1.200', 'cuota vencida el $vencida'), findsOneWidget);
                  expect(_cuotaVencida, findsOneWidget);
                case Estado591.hoy:
                  // La cuota de hoy todavía no venció.
                  expect(_linea('1.200', 'cuota ${corto591(dia591(0, hora: 9))}'), findsOneWidget);
                  expect(_cuotaVencida, findsNothing);
                case Estado591.sinPlan:
                  expect(_soloDebe, findsOneWidget);
                  expect(find.textContaining('cuota'), findsNothing);
                case Estado591.sinSaldoConCuota:
                  // Quien no debe nada no lleva cuota, ni «Debe», ni «$ Cobrar».
                  expect(find.textContaining('cuota'), findsNothing);
                  expect(find.textContaining('Debe'), findsNothing);
                  expect(find.byKey(ClavesHojaCasa.cobrar), findsNothing);
                case Estado591.mixta:
                  expect(_linea('1.200', 'cuota vencida el $vencida'), findsOneWidget);
                  expect(_cuotaVencida, findsOneWidget);
                  if (arriba) {
                    expect(_linea('500,50', 'cuota $proxima'), findsOneWidget);
                    expect(find.text('Ana Gómez'), findsOneWidget);
                  } else {
                    // El resumen muestra solo la persona que más debe.
                    expect(_linea('500,50', 'cuota $proxima'), findsNothing);
                  }
                case Estado591.larga:
                  expect(find.textContaining('Maximiliano Alejandro'), findsOneWidget);
                  expect(find.textContaining('cuota vencida el $vencida'), findsOneWidget);
                case Estado591.sesentaConCuota:
                  expect(find.byType(FilaPersonaDeLaCasa), findsNWidgets(arriba ? 60 : 1));
              }
            });
          }
        }
      }
    }
  });

  group('Lector de pantalla', () {
    testWidgets('C·02 · la fila oye nombre, monto, cuota y que venció', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA591(tester, Estado591.vencida, tamano: t412x915, escala: 1, arriba: true);
      await asentar445(tester);

      final fila = tester.getSemantics(find.byKey(ClavesHojaCasa.persona).first);
      expect(fila.label, contains('Pedro Gómez'));
      expect(fila.label, contains('cuota vencida el ${dm591(dia591(-2))}'));
      semantica.dispose();
    });

    testWidgets('C·01 · el resumen expone la línea de la cuota como texto', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA591(tester, Estado591.vencida, tamano: t412x915, escala: 1, arriba: false);
      await asentar445(tester);

      expect(
        find.bySemanticsLabel(RegExp('cuota vencida el ${RegExp.escape(dm591(dia591(-2)))}')),
        findsWidgets,
      );
      semantica.dispose();
    });
  });

  group('Contraste de la cuota vencida', () {
    test(
      'el ámbar del aviso (30A-06) llega a 4,5:1 sobre blanco y sobre el fondo de las tarjetas',
      () {
        expect(_contraste(ColoresAlta.ambar, Colors.white), greaterThanOrEqualTo(4.5));
        expect(_contraste(ColoresAlta.ambar, const Color(0xFFF2F6FB)), greaterThanOrEqualTo(4.5));
      },
    );
  });

  group('«\$ Cobrar» sigue a mano con la cuota en la línea', () {
    for (final escala in _escalas) {
      testWidgets('C·01 · cuota vencida · «\$ Cobrar» alcanzable y abre el cobro ×$escala', (
        tester,
      ) async {
        await cargarFuentes205(tester);
        final m = await llegarA591(
          tester,
          Estado591.vencida,
          tamano: t360x640,
          escala: escala,
          arriba: false,
        );
        await asentar445(tester);

        final boton = find.byKey(ClavesHojaCasa.cobrar);
        await tester.ensureVisible(boton);
        await tester.pump();
        await tester.tap(boton);
        await tester.pump();

        expect(m.cobros, hasLength(1));
        expect(m.cobros.single.personaId, 'p-pedro');
      });
    }
  });
}

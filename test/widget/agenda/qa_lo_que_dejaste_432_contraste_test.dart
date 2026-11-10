// QA de #432: contraste de texto del paso «Lo que dejaste». Va aparte y con la letra de prueba: con
// las fuentes reales `textContrastGuideline` da falsos negativos (lee el fondo de una captura con
// glifos reales).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/misionero_dejado.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_venta_432_arnes.dart';

void main() {
  usarFuentesReales = false;
  const misioneros = [
    MisioneroParaDejar(productoId: 'p-1', nombre: 'El camino a Cristo'),
    MisioneroParaDejar(productoId: 'p-2', nombre: 'La gran esperanza'),
  ];

  Future<void> montar(WidgetTester tester, {bool conError = false}) async {
    tester.view.physicalSize = telefonoGrande;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => mostrarHojaTerminoEntrevista(
                  context,
                  direccion: 'Grecia 3305',
                  persona: 'Rosa Díaz',
                  entrada: DateTime(2026, 10, 23, 14, 23),
                  salida: DateTime(2026, 10, 23, 14, 41),
                  entradaInferida: false,
                  reloj: () => DateTime(2026, 10, 23, 14, 41),
                  misioneros: misioneros,
                  alGuardar: (e, s, m) async => conError ? const FailureInesperado() : null,
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('el paso 1 (R·06) cumple el contraste de texto', (tester) async {
    final h = tester.ensureSemantics();
    await montar(tester);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    h.dispose();
  });

  testWidgets('el paso 2 vacío y con una cantidad cumple el contraste de texto', (tester) async {
    final h = tester.ensureSemantics();
    await montar(tester);
    await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await tester.tap(find.byTooltip('Uno más de El camino a Cristo'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    h.dispose();
  });

  testWidgets('el paso 2 con el aviso de error cumple el contraste de texto', (tester) async {
    final h = tester.ensureSemantics();
    await montar(tester, conError: true);
    await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Uno más de El camino a Cristo'));
    await tester.pump();
    await tester.tap(find.byKey(ClavesEntrevista.guardarLoQueDejaste));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    h.dispose();
  });
}

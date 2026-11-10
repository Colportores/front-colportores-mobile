// QA de accesibilidad de «Registrar venta» (vista 27, HU-VEN-001, #158, PR #531): las cuatro guías de
// Flutter (tamaño de toque de Android e iOS, etiquetas y contraste) en cada estado, 360×640 y
// 412×915, texto 1,0 y 2,0. Va aparte de `qa_vista27_venta_158_test.dart` porque la guía de contraste
// da falsos negativos con las fuentes reales (se usa la fuente de prueba).
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart'
    show TextosVenta;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista27_venta_158_arnes.dart';
import '../../helpers/venta_ui_falsos.dart';

void main() {
  setUpAll(() => usarFuentesReales408 = false);
  tearDownAll(() => usarFuentesReales408 = true);

  const tamanos = {'360x640': chico531, '412x915': grande531};

  group('Guías de accesibilidad por estado', () {
    for (final estado in Estado531.values) {
      for (final t in tamanos.entries) {
        for (final escala in const [1.0, 2.0]) {
          testWidgets('${estado.titulo} · ${t.key} · ×$escala', (tester) async {
            final semantica = tester.ensureSemantics();
            await llegar531(tester, estado, tamano: t.value, escala: escala);
            // Con la fuente de prueba (más ancha que Inter) el diálogo de salida desborda a 2,0: el
            // overflow se mide con las fuentes reales en `qa_vista27_venta_158_test.dart`.
            final error = tester.takeException();
            if (estado != Estado531.confirmaSalida) expect(error, isNull);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });

  group('Semántica de lo que se anuncia', () {
    testWidgets('27A·13: el aviso de error se anuncia como región viva', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegar531(tester, Estado531.a13ErrorAlGuardar);
      final nodo = tester.getSemantics(find.byKey(const Key('venta_error')));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      semantica.dispose();
    });

    testWidgets('27A·11: el error del talonario se anuncia como región viva', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegar531(tester, Estado531.a11TalonarioRepetido);
      final texto = find.textContaining('Ya usaste el talonario');
      final nodo = tester.getSemantics(texto);
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      semantica.dispose();
    });

    testWidgets('el botón «Registrar venta» apagado queda como deshabilitado para el lector', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llegar531(tester, Estado531.a05Venta);
      await tester.enterText(campo531('venta_talonario'), '');
      await asentar(tester);
      expect(
        tester.getSemantics(cta531),
        isSemantics(isButton: true, isEnabled: false, hasEnabledState: true),
      );
      semantica.dispose();
    });

    testWidgets('«Guardando»: la ruedita tiene un anuncio, no es un botón mudo', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegar531(tester, Estado531.guardando);
      final nodo = tester.getSemantics(cta531);
      expect(
        nodo.label.isNotEmpty || nodo.flagsCollection.isLiveRegion,
        isTrue,
        reason: 'con el guardado en curso, el botón no dice nada',
      );
      expect(nodo.label, contains(TextosVenta.guardando));
      semantica.dispose();
    });
  });
}

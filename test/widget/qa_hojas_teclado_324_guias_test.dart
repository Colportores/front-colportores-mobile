// QA de #324 / PR #342 (vistas 03 y 07 con el teclado abierto): guías de accesibilidad de Flutter en
// todos los estados, no solo en los cuatro del alta que ya mira `alta_ubicacion_qa_320_guias_test.dart`.
//
// Va aparte de `qa_hojas_teclado_324_test.dart` porque `textContrastGuideline` da falsos negativos con las
// fuentes reales (el texto antialiasado mezcla el color con el fondo): acá se usa la fuente de prueba y
// solo se mira el color, el tamaño de toque y las etiquetas.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:dartz/dartz.dart' show Left;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_317_arnes.dart' as a;
import '../helpers/modificar_ubicacion_qa_307_arnes.dart' as m;
import '../helpers/qa_hojas_teclado_324_arnes.dart';

/// Las cuatro guías, con el tamaño de toque de Android solo donde el mapa deja a «Cerrar» sus 48 dp.
Future<void> _guias(WidgetTester tester, {bool androidTap = true}) async {
  if (androidTap) await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  if (androidTap) await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  group('QA #324 · 03 · guías con el teclado abierto en los seis estados', () {
    for (final estado in a.EstadoAlta.values) {
      for (final t in telefonos) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('${estado.rotulo} · ${t.nombre} · ${veces(escala)}', (tester) async {
            final handle = tester.ensureSemantics();
            await a.abrirEn(tester, estado, tamano: t.tamano, escala: escala, teclado: t.teclado);
            await tester.tap(a.campoNumero);
            await a.asentar(tester);
            await _guias(tester);
            handle.dispose();
          });
        }
      }
    }
  });

  group('QA #324 · 03 · guías con el aviso de error del guardado y el teclado vuelto a abrir', () {
    for (final t in telefonos) {
      testWidgets('no pudimos guardar · ${t.nombre} · 2×', (tester) async {
        final handle = tester.ensureSemantics();
        final montada = await a.abrirEn(
          tester,
          a.EstadoAlta.gpsPreciso,
          tamano: t.tamano,
          escala: 2,
          teclado: t.teclado,
        );
        montada.repo.comportamiento = (_) async => const Left(FailureInesperado());
        await tester.ensureVisible(find.text('Casa'));
        await tester.pump();
        await tester.tap(find.text('Casa'));
        await a.asentar(tester);
        if (a.botonRegistrarFijo.evaluate().isNotEmpty) {
          await tester.tap(a.botonRegistrarFijo);
          await m.asentarConTeclado(tester);
        }
        expect(find.text(TextosAlta.noPudimosGuardar), findsOneWidget);
        await tester.tap(a.campoNumero);
        m.ponerTeclado(tester, t.teclado);
        await m.asentar(tester);
        await _guias(tester);
        handle.dispose();
      });
    }
  });

  group('QA #324 · 07 · guías con el teclado abierto', () {
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0, 3.0]) {
        // Con texto 3× en 360×640 la hoja llega al 80 % y de «Cerrar» quedan 36 dp de 48 (ver
        // `qa_hojas_teclado_324_test.dart`): la decisión del PR #342 lo acepta (AA se cumple; el atrás
        // del sistema cierra el teclado y lo deja entero), así que no se exigen las guías de toque de
        // Android (48) ni de iOS (44). Las de etiquetas y contraste sí.
        final cerrarChico = t.tamano.width == 360 && escala >= 3;
        testWidgets('07·01 Editar datos · ${t.nombre} · ${veces(escala)}', (tester) async {
          final handle = tester.ensureSemantics();
          await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
          await m.abrirTeclado(tester, alto: t.teclado);
          await tester.tap(m.campoNumero);
          await m.asentar(tester);
          await _guias(tester, androidTap: !cerrarChico);
          handle.dispose();
        });
      }
    }

    testWidgets(
      '07 · aviso «cambió mientras la editabas» con el teclado de por medio · 360×640 · 2×',
      (tester) async {
        final handle = tester.ensureSemantics();
        final montada = await m.abrirEdicion(tester, escala: 2);
        await m.fallarPorCambio(tester, montada, conTeclado: true);
        await _guias(tester);
        handle.dispose();
      },
    );

    testWidgets('07·02 Mover el punto · 360×640 · 2×', (tester) async {
      final handle = tester.ensureSemantics();
      await abrirEdicionQa(tester, escala: 2);
      await tester.ensureVisible(find.text('Mover el punto'));
      await tester.pump();
      await tester.tap(find.text('Mover el punto'));
      await m.asentar(tester);
      await _guias(tester);
      handle.dispose();
    });

    testWidgets('07·04 Salir con cambios sin guardar · 360×640 · 2×', (tester) async {
      final handle = tester.ensureSemantics();
      await abrirEdicionQa(tester, escala: 2);
      await tester.enterText(m.campoNumero, '1240');
      await m.asentar(tester);
      await tester.tap(find.byTooltip('Cerrar'));
      await m.asentar(tester);
      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
      await _guias(tester);
      handle.dispose();
    });
  });
}

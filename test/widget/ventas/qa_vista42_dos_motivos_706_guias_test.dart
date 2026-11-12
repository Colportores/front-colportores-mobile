// QA de «Dos motivos» (vista 42B·09C, #706): las guías de accesibilidad de Flutter (tamaño de toque de
// Android e iOS, etiqueta en cada toque y contraste del texto) con el motivo de antes, a 360×640 y
// 412×915. Con la letra de prueba (Ahem): el contraste con la letra real da falsos negativos.
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista42_venta_crece_693_arnes.dart';
import '../../helpers/venta_ui_falsos.dart';

Finder _campo(String clave) =>
    find.descendant(of: find.byKey(Key(clave)), matching: find.byType(TextField));

Future<void> _guias(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

Future<void> _abrir(WidgetTester tester, {required String motivo, required Size tamano}) async {
  final venta = ventaAbierta693('v-39', motivo: motivo, total: 110000, cobrado: 0);
  final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [venta]));
  await montarNuevaVenta(tester, e, creceSobre: venta, tamano: tamano);
  await tocar(tester, find.text('Libros'));
  await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
  await tocar(tester, find.text(TextosVenta.agregarALaVenta));
  await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));
  await escribir(tester, _campo('venta_monto'), '1.500');
  await escribir(tester, _campo('venta_motivo'), 'descuento del libro nuevo');
}

void main() {
  group('09C · guías de accesibilidad con el motivo de antes', () {
    for (final t in const [
      (nombre: '360x640', tamano: telefonoChico693),
      (nombre: '412x915', tamano: telefonoGrande693),
    ]) {
      testWidgets('${t.nombre}: monto abierto con el motivo de antes', (tester) async {
        await _abrir(tester, motivo: 'redondeo', tamano: t.tamano);

        await _guias(tester);
      });

      testWidgets('${t.nombre}: con el aviso de que no entran los dos motivos', (tester) async {
        await _abrir(tester, motivo: 'v' * 480, tamano: t.tamano);

        await _guias(tester);
      });
    }
  });
}

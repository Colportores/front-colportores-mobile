// El botón principal de las vistas de venta mientras guarda: el lector de pantalla dice qué pasa una
// sola vez (la ruedita no repite el texto que ya está al lado).
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart'
    show TextosVenta;
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_venta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _montar(WidgetTester tester, {String? textoOcupado}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: BotonDeVenta(
        texto: 'Registrar venta',
        alPresionar: () {},
        ocupado: true,
        textoOcupado: textoOcupado,
      ),
    ),
  ),
);

void main() {
  group('BotonDeVenta ocupado', () {
    testWidgets('con texto al lado, «Registrando…» se lee una sola vez', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, textoOcupado: 'Registrando…');

      final nodo = tester.getSemantics(find.byKey(const Key('venta_cta')));
      expect(nodo.label, 'Registrando…');
      semantica.dispose();
    });

    testWidgets('sin texto al lado, la ruedita anuncia «Guardando la venta»', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);

      final nodo = tester.getSemantics(find.byKey(const Key('venta_cta')));
      expect(nodo.label, TextosVenta.guardando);
      semantica.dispose();
    });
  });
}

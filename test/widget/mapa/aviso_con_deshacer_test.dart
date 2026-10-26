// El aviso con «Deshacer» compartido (canvas 39, R·01): tarjeta flotante de radio 14, «✓» verde antes
// del texto y la acción en azul claro sobre tinta. Lo usan «Guardado» de «¿Qué pasó?» y «reactivada»
// de la lista (vista 09).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_con_deshacer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista10_arnes.dart' show contraste208;

const _plazo = Duration(seconds: 8);

/// Monta una pantalla con un botón que muestra el aviso; devuelve cuántos «Deshacer» hubo.
Future<List<int>> _montar(
  WidgetTester tester, {
  double escala = 1.0,
  bool lector = false,
  Size tamano = const Size(360, 640),
  String texto = 'Guardado. Grecia 3307 quedó como «No contestó».',
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final deshechos = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      builder: (context, hijo) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(escala), accessibleNavigation: lector),
        child: hijo!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => mostrarAvisoConDeshacer(
                ScaffoldMessenger.of(context),
                mediaQuery: MediaQuery.of(context),
                texto: texto,
                etiquetaDeshacer: 'Deshacer',
                duracion: _plazo,
                alDeshacer: () => deshechos.add(deshechos.length),
              ),
              child: const Text('mostrar'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('mostrar'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return deshechos;
}

void main() {
  testWidgets('dado el canvas R·01, cuando se muestra, es una tarjeta de radio 14 sobre tinta con '
      '«✓» verde, el texto y «Deshacer» en azul claro', (tester) async {
    await _montar(tester);

    final aviso = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(aviso.backgroundColor, ColoresAvisoDeshacer.fondo);
    expect(aviso.behavior, SnackBarBehavior.floating);
    expect(
      aviso.shape,
      isA<RoundedRectangleBorder>().having(
        (f) => f.borderRadius,
        'radio',
        BorderRadius.circular(14),
      ),
    );
    expect(ColoresAvisoDeshacer.fondo, const Color(0xFF0E1A2B));
    expect(ColoresAvisoDeshacer.tilde, const Color(0xFF9FD3AE));
    expect(ColoresAvisoDeshacer.accion, const Color(0xFFB9D3F2));
    expect(tester.widget<Text>(find.byKey(ClavesAvisoDeshacer.tilde)).data, '✓');
    expect(find.text('Guardado. Grecia 3307 quedó como «No contestó».'), findsOneWidget);
    expect(aviso.action?.textColor, ColoresAvisoDeshacer.accion);
    // El «✓» va antes del texto.
    expect(
      tester.getTopLeft(find.byKey(ClavesAvisoDeshacer.tilde)).dx,
      lessThan(tester.getTopLeft(find.byKey(ClavesAvisoDeshacer.texto)).dx),
    );
  });

  testWidgets('dado los tres colores, cuando se miden sobre la tinta, pasan 4,5:1 (WCAG 1.4.3)', (
    tester,
  ) async {
    for (final color in [
      ColoresAvisoDeshacer.texto,
      ColoresAvisoDeshacer.tilde,
      ColoresAvisoDeshacer.accion,
    ]) {
      expect(contraste208(color, ColoresAvisoDeshacer.fondo), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('dado el «✓», cuando lo lee el lector de pantalla, no lo dice: es decoración', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await _montar(tester);

    expect(find.bySemanticsLabel('✓'), findsNothing);
    semantica.dispose();
  });

  testWidgets('dado el aviso, cuando se toca «Deshacer», quien lo mostró recibe el toque', (
    tester,
  ) async {
    final deshechos = await _montar(tester);

    await tester.tap(find.text('Deshacer'));
    await tester.pump();

    expect(deshechos, hasLength(1));
  });

  testWidgets('dado el aviso, cuando pasan 8 segundos sin lector, se cierra solo', (tester) async {
    await _montar(tester);

    await tester.pump(_plazo - const Duration(seconds: 2));
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('dado un lector de pantalla, cuando pasan 30 segundos, el aviso sigue (WCAG 2.2.1)', (
    tester,
  ) async {
    await _montar(tester, lector: true);

    await tester.pump(const Duration(seconds: 30));

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('dado un segundo aviso, cuando se muestra, reemplaza al primero', (tester) async {
    await _montar(tester);
    await tester.tap(find.text('mostrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Deshacer'), findsOneWidget);
  });

  for (final escala in [1.5, 2.0]) {
    testWidgets(
      'dado el texto al ${(escala * 100).round()} %, cuando se muestra, «Deshacer» va debajo '
      'del texto, entra en pantalla y se puede tocar',
      (tester) async {
        final deshechos = await _montar(tester, escala: escala, tamano: const Size(320, 568));

        final texto = tester.getRect(find.byKey(ClavesAvisoDeshacer.texto));
        final accion = tester.getRect(find.text('Deshacer'));
        expect(accion.top, greaterThanOrEqualTo(texto.bottom - 1));
        expect(accion.right, lessThanOrEqualTo(320));
        expect(accion.bottom, lessThanOrEqualTo(568));
        // El «✓» queda antes de «Deshacer»: a su izquierda o, si no entran juntos, en el renglón de arriba.
        final tilde = tester.getRect(find.byKey(ClavesAvisoDeshacer.tilde));
        expect(tilde.right <= accion.left || tilde.bottom <= accion.top + 1, isTrue);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Deshacer'));
        await tester.pump();
        expect(deshechos, hasLength(1));
      },
    );
  }
}

// QA de #379 (PR #390): las guías de accesibilidad de Flutter sobre los avisos de «Modificar ubicación»,
// tanto en el aviso de siempre como en el grande que ahora sale desde 1,8× en teléfonos de 320–340 dp.
//
// Sin las fuentes reales: con ellas `textContrastGuideline` da falsos negativos (los glifos de prueba son
// cuadrados llenos). La medida de las palabras y la captura están en `qa_avisos_modificar_379_test.dart`.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/dialogos_modificar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

class _Anfitrion extends StatelessWidget {
  const _Anfitrion(this.abrir);

  final Future<bool> Function(BuildContext) abrir;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(onPressed: () => abrir(context), child: const Text('abrir')),
    ),
  );
}

final _avisos = <(String, Future<bool> Function(BuildContext))>[
  ('descartar', (c) => confirmarDescartarCambios(c, ['el tipo', 'el número'])),
  (
    'confirmar',
    (c) => confirmarModificacion(c, texto: ModificacionRequiereConfirmacion.avisoCambioCiudad),
  ),
];

const _estados = <(Size, double)>[
  (Size(360, 640), 1.0),
  (Size(360, 640), 2.0),
  (Size(412, 915), 1.0),
  (Size(412, 915), 2.0),
  (Size(320, 568), 1.0),
  (Size(320, 568), 1.8),
  (Size(320, 568), 1.9),
  (Size(320, 568), 2.0),
  (Size(340, 640), 2.0),
  (Size(360, 640), 3.0),
];

Future<void> _abrir(
  WidgetTester tester,
  Future<bool> Function(BuildContext) abrir,
  Size tamano,
  double escala,
) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: _Anfitrion(abrir),
    ),
  );
  await tester.tap(find.text('abrir'));
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  for (final (nombre, abrir) in _avisos) {
    for (final (tamano, escala) in _estados) {
      final donde = '$nombre · ${tamano.width.round()}×${tamano.height.round()} · ×$escala';

      testWidgets('$donde: tamaño de toque, nombre de cada botón y contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        await _abrir(tester, abrir, tamano, escala);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });

      testWidgets('$donde: los dos botones tienen acción y el aviso tapa lo de abajo', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await _abrir(tester, abrir, tamano, escala);
        final botones = [
          nombre == 'descartar' ? 'Seguir editando' : 'Cancelar',
          nombre == 'descartar' ? 'Descartar' : 'Confirmar',
        ];
        for (final b in botones) {
          final datos = tester.getSemantics(find.text(b)).getSemanticsData();
          expect(datos.label, b);
          expect(datos.hasAction(SemanticsAction.tap), isTrue, reason: '«$b» sin acción de tocar');
          expect(datos.hasAction(SemanticsAction.focus), isTrue, reason: '«$b» sin foco');
        }
        // El aviso tapa a la pantalla de abajo para el lector: no sigue leyendo «abrir».
        expect(
          tester.getSemantics(find.text('abrir')).owner,
          isNull,
          reason: 'queda fuera del árbol',
        );
        semantica.dispose();
      });
    }
  }
}

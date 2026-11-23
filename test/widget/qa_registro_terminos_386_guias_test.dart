// QA de #386 (PR #758): guías de accesibilidad con el aviso de «términos de uso» a la vista. Va en un
// archivo aparte del que carga las fuentes reales: con ellas `textContrastGuideline` da falsos
// negativos (el mismo isolate conserva las fuentes cargadas por el test anterior).
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_registro_terminos_386_arnes.dart';

const _tamanios = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];
const _escalas = <double>[1, 2];

void main() {
  late AbridorFalso386 abridor;
  late MonitorFalso386 monitor;

  setUp(() {
    abridor = AbridorFalso386();
    monitor = MonitorFalso386();
  });

  for (final (nombreTam, tam) in _tamanios) {
    for (final escala in _escalas) {
      testWidgets(
        'tamaño de toque, etiquetas y contraste con el aviso de «sin conexión» a la vista '
        '($nombreTam, texto ${escala}x)',
        (tester) async {
          final semantica = tester.ensureSemantics();
          monitor.tipo = TipoConexion.sinConexion;
          await montar386(tester, tamanio: tam, abridor: abridor, monitor: monitor, escala: escala);
          await tocarEnlace386(tester);
          expect(find.text(avisoSinConexion386), findsOneWidget);
          // Se vuelve al inicio del formulario: un nodo medio tapado por la barra al desplazar
          // daría un contraste falso.
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
          await tester.pump();

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        },
      );
    }
  }
}

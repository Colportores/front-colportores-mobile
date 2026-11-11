// QA del aviso de privacidad con «No volver a mostrar» dentro del alta de persona real (32A, #445, PR
// #476; decisión de Cristian 23/10 «Aviso privado»): cada estado del aviso en la matriz de tamaños y
// escalas, con fuentes reales y capturas (`--dart-define=QA_CAPTURAS=true`).
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_persona.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_445_arnes.dart';
import '../../helpers/qa_vista39_445_aviso_arnes.dart';

const _literal = 'Estos datos solo viven en tu celular. Nunca se suben a la nube.';

void main() {
  for (final estado in EstadoAviso445.values) {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        final sufijo = sufijo445(tamano, escala);
        testWidgets('alta 32A con el aviso ${estado.name} · $sufijo', (tester) async {
          await cargarFuentes205(tester);
          await llegarAlAviso445(tester, estado, tamano: tamano, escala: escala);

          expect(tester.takeException(), isNull);
          expect(find.text('Nueva persona'), findsOneWidget);
          switch (estado) {
            case EstadoAviso445.visible:
              expect(find.text(_literal), findsOneWidget);
              expect(find.text('No volver a mostrar'), findsOneWidget);
              expect(
                tester.getSize(find.byKey(ClavesAvisoPrivacidad.noVolverAMostrar)).height,
                greaterThanOrEqualTo(48),
              );
            case EstadoAviso445.recienEscondido:
              expect(find.text(_literal), findsNothing);
              expect(find.byKey(ClavesAvisoPrivacidad.escondido), findsOneWidget);
              expect(find.textContaining('Configuración'), findsOneWidget);
            case EstadoAviso445.falla:
              expect(find.text(_literal), findsOneWidget);
              expect(find.text('No pudimos guardar tu elección. Probá de nuevo.'), findsOneWidget);
            case EstadoAviso445.oculto:
              expect(find.text(_literal), findsNothing);
              expect(find.byKey(ClavesAvisoPrivacidad.escondido), findsNothing);
          }
          await capturar445(tester, 'aviso_${estado.name}_$sufijo');
        });
      }
    }
  }
}

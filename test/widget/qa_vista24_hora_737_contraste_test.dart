// QA de #737 (PR #744): contraste del texto con el aviso de «cuál hora falló» y con las horas en su fila
// nueva. Va aparte y con la letra de prueba: con las fuentes reales la guía da falsos negativos.
import 'package:colportores_mobile/features/notificaciones/domain/repositories/avisos_del_servidor_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista24_avisos_516_arnes.dart';

void main() {
  for (final tam in tamanos736) {
    // Solo a 1,0x: el selector de hora del sistema con la letra de prueba desborda a 2,0x (no es de la app).
    for (final escala in [1.0]) {
      testWidgets(
        'error de la hora de las visitas de mañana · ${tam.nombre} · ${escala}x: contraste',
        (tester) async {
          final semantica = tester.ensureSemantics();
          final telefono = await llevarAlEstado736(
            tester,
            Estado736.preferencias,
            tamano: tam,
            escala: escala,
          );
          telefono.avisos.fallaAlGuardar = const AvisosServidorException();
          await tocar736(tester, horaAgenda736);
          await tester.pumpAndSettle();
          await elegirHora736(tester, 21, 15);
          expect(errorGuardar736, findsOneWidget);
          await tester.pump(const Duration(milliseconds: 400));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        },
      );
    }
  }
}

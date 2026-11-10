// QA de #679, casilla 5 «Ver bajas»: tras «Dar de baja» a una persona de una casa, el aviso le
// promete que la encuentra en «Ver bajas» y la puede reactivar; la entrada tiene que existir en la
// pestaña «Personas» de la hoja de la casa (decisión del 10/11, P1 del pendiente del implementador:
// el mismo «Mostrar bajas» de 32D·04, solo si hay bajas).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista39_445_arnes.dart';

void main() {
  testWidgets(
    'dado una persona de la casa dada de baja, cuando se abre la pestaña «Personas» de la hoja, '
    'hay un «Mostrar bajas» para llegar a ella y reactivarla (32D·04/32D·05)',
    (tester) async {
      final m = Montaje445();
      m.repo.sembrar([clienteDeBajaDePersonas('p-luis', 'Luis', apellido: 'Pérez')]);
      await montarHoja445(tester, montaje: m);
      await asentar445(tester);

      expect(find.text('Mostrar bajas'), findsOneWidget);
    },
  );
}

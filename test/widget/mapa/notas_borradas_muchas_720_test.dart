// #720: «Ver borradas» de una persona con más de 25 notas (se guardan 90 días). La lista se arma
// perezosa, se llega a la última nota y el texto al 200 % no desborda.
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_persona_falsos.dart';
import 'notas_persona_arnes.dart';

const _cuantas = 60;

String _id(int i) => 'b-${i.toString().padLeft(2, '0')}';

/// 60 notas borradas, una por día de las últimas semanas (la 0 es la de ayer).
NotaPersonaRepositorioFalso _repo() => NotaPersonaRepositorioFalso(
  notas: [
    for (var i = 0; i < _cuantas; i++)
      notaDePrueba(
        _id(i),
        'Nota borrada número $i',
        creada: DateTime(2026, 10, 21).subtract(Duration(days: i % 80)),
        borrada: DateTime(2026, 10, 21, 10).subtract(Duration(days: i % 80)),
      ),
  ],
);

Future<void> _abrirBorradas(WidgetTester tester, {double escala = 1}) async {
  await montarNotas(tester, repo: _repo(), escala: escala);
  final ver = find.text('Ver borradas ($_cuantas)');
  // Con el texto al 200 % el enlace queda debajo de las notas activas.
  await tester.scrollUntilVisible(ver, 200, scrollable: find.byType(Scrollable).first);
  await tester.tap(ver);
  await asentar(tester);
}

Finder get _tarjetas => find.byType(TarjetaNota);

void main() {
  group('#720 Notas borradas con 60 registros', () {
    testWidgets('arma las tarjetas que se ven y no las 60', (tester) async {
      await _abrirBorradas(tester);

      expect(_tarjetas, findsWidgets);
      expect(_tarjetas.evaluate().length, lessThan(_cuantas));
      expect(find.byKey(ValueKey('borrada_${_id(0)}')), findsOneWidget);
      expect(find.byKey(ValueKey('borrada_${_id(_cuantas - 1)}')), findsNothing);
    });

    testWidgets('se llega a la última nota desplazando', (tester) async {
      await _abrirBorradas(tester);

      await tester.scrollUntilVisible(
        find.byKey(ValueKey('borrada_${_id(_cuantas - 1)}')),
        300,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.byKey(ValueKey('borrada_${_id(_cuantas - 1)}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('al 200 % se llega a la última nota sin desbordes', (tester) async {
      await _abrirBorradas(tester, escala: 2);

      await tester.scrollUntilVisible(
        find.byKey(ValueKey('borrada_${_id(_cuantas - 1)}')),
        300,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 200,
      );

      expect(find.byKey(ValueKey('borrada_${_id(_cuantas - 1)}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

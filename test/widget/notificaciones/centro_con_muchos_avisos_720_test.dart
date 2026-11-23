// #720: el centro de notificaciones con más de 25 avisos. La lista es perezosa (arma lo que se ve), se
// llega al aviso más viejo, «Marcar todas como leídas» y «Borrar todas» alcanzan a los 60 y el
// texto al 200 % no desborda.
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/fila_notificacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/historial_notificaciones_falsos.dart';

const _cuantos = 60;

String _id(int i) => 'n-${i.toString().padLeft(2, '0')}';

/// 60 avisos, uno cada 5 horas (el 0 es el más nuevo), los pares sin leer.
List<Notificacion> _sesenta() => [
  for (var i = 0; i < _cuantos; i++)
    aviso(
      _id(i),
      hace: Duration(hours: 1 + i * 5),
      titulo: 'Cobranza número $i',
      leida: i.isOdd,
    ),
];

Future<void> _alFinal(WidgetTester tester) async {
  // La fila «Tipo de aviso» (#484) suma alto al principio de la lista: más pasos que los 50 de siempre.
  await tester.scrollUntilVisible(
    filaDe(_id(_cuantos - 1)),
    400,
    scrollable: _scrollable,
    maxScrolls: 100,
  );
  await tester.pump();
}

Finder get _scrollable => find.descendant(of: centroLista, matching: find.byType(Scrollable));

void main() {
  group('#720 Centro de notificaciones con 60 avisos', () {
    testWidgets('arma solo lo que se ve y lo más nuevo queda arriba', (tester) async {
      await abrirCentro(tester, CentroArnes(avisos: _sesenta()));

      expect(find.byType(FilaNotificacion), findsWidgets);
      expect(find.byType(FilaNotificacion).evaluate().length, lessThan(30));
      expect(filaDe(_id(0)), findsOneWidget);
      expect(filaDe(_id(_cuantos - 1)), findsNothing);
      expect(find.text('HOY'), findsOneWidget);
    });

    testWidgets('se llega al aviso más viejo y los rótulos de día no se repiten', (tester) async {
      await abrirCentro(tester, CentroArnes(avisos: _sesenta()));

      await _alFinal(tester);

      expect(filaDe(_id(_cuantos - 1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Marcar todas como leídas» alcanza a los 60 con un solo llamado', (tester) async {
      final arnes = CentroArnes(avisos: _sesenta());
      await abrirCentro(tester, arnes);

      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();

      expect(arnes.historial.llamadasMarcarTodas, 1);
      expect(arnes.historial.filas.where((f) => !f.leida), isEmpty);
      expect(arnes.historial.filas, hasLength(_cuantos));
    });

    testWidgets('«Borrar todas» pide confirmar y borra los 60', (tester) async {
      final arnes = CentroArnes(avisos: _sesenta());
      await abrirCentro(tester, arnes);

      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.tap(menuBorrarTodas);
      await tester.pumpAndSettle();
      expect(arnes.historial.filas, hasLength(_cuantos));
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();

      expect(arnes.historial.filas, isEmpty);
      expect(centroVacio, findsOneWidget);
    });

    testWidgets('al 200 % se llega al último aviso sin desbordes', (tester) async {
      await abrirCentro(tester, CentroArnes(avisos: _sesenta()), texto: 2);

      await _alFinal(tester);

      expect(filaDe(_id(_cuantos - 1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('llega un aviso nuevo con la lista larga abierta y queda arriba', (tester) async {
      final arnes = CentroArnes(avisos: _sesenta());
      await abrirCentro(tester, arnes);

      arnes.historial.llegaUno(aviso('n-nuevo', hace: Duration.zero, titulo: 'Recién llegado'));
      await tester.pumpAndSettle();

      expect(filaDe('n-nuevo'), findsOneWidget);
      expect(
        tester.getTopLeft(filaDe('n-nuevo')).dy,
        lessThan(tester.getTopLeft(filaDe(_id(0))).dy),
      );
    });
  });
}

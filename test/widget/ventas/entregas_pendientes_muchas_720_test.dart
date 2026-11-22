// #720: «Entregas pendientes» con más de 25 registros. La lista se construye perezosa (solo se
// arman, y piden su rótulo a la base, las tarjetas que se ven), el orden de los grupos se mantiene
// y se llega a la última tarjeta con el texto al 200 %.
import 'package:colportores_mobile/features/inicio/presentation/widgets/barra_pestanas_inicio.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregas_pendientes_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_entrega_diferida.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';

const _porGrupo = 20;

/// 20 atrasadas, 20 próximas y 20 sin fecha, cada una de su propia venta.
List<EntregaPendiente> _sesenta() => [
  for (var i = 0; i < _porGrupo; i++)
    pendienteDe(
      'a-$i',
      fecha: DateTime(2026, 10, 1 + i % 20, 10),
      vinculo: 'ep-${1 + i % 3}',
      lineas: [lineaDe('e-a-$i', 'p-hijos')],
    ),
  for (var i = 0; i < _porGrupo; i++)
    pendienteDe(
      'p-$i',
      fecha: DateTime(2026, 11, 1 + i, 9),
      vinculo: 'ep-${1 + i % 3}',
      lineas: [lineaDe('e-p-$i', 'p-salud')],
    ),
  for (var i = 0; i < _porGrupo; i++)
    pendienteDe('s-$i', vinculo: 'ep-${1 + i % 3}', lineas: [lineaDe('e-s-$i', 'p-hijos')]),
];

Route<PestanaInicio> _ruta() => EntregasPendientesPage.ruta(colportorId: 'col-1');

EntornoDeEntrega _entorno(List<EntregaPendiente> lista) {
  final e = EntornoDeEntrega();
  e.entregas.emitirPendientes(lista);
  return e;
}

Finder get _tarjetas => find.byType(TarjetaDeEntregaPendiente);

Finder get _lista => find.byKey(const Key('entregas_lista'));

/// Baja al fondo de la lista.
Future<void> _alFondo(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: _lista, matching: find.byType(Scrollable)),
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('#720 Entregas pendientes con 60 registros', () {
    testWidgets('la lista es perezosa: arma las tarjetas que se ven y no las 60', (tester) async {
      await montarPantalla(tester, _entorno(_sesenta()), _ruta);

      expect(_tarjetas, findsWidgets);
      expect(_tarjetas.evaluate().length, lessThan(30));
      expect(find.text('ATRASADAS'), findsOneWidget);
    });

    testWidgets('al fondo está el grupo «sin fecha» con su «Poner fecha», en orden', (
      tester,
    ) async {
      await montarPantalla(tester, _entorno(_sesenta()), _ruta);

      expect(find.text('Poner fecha'), findsNothing);
      await _alFondo(tester);

      expect(find.text('Poner fecha'), findsWidgets);
      expect(find.text('ATRASADAS'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('los tres rótulos se encuentran bajando de a poco y en orden', (tester) async {
      await montarPantalla(tester, _entorno(_sesenta()), _ruta);

      final orden = <String>[];
      for (var paso = 0; paso < 60; paso++) {
        for (final r in ['ATRASADAS', 'PRÓXIMAS', 'SIN FECHA']) {
          if (find.text(r).evaluate().isNotEmpty && !orden.contains(r)) orden.add(r);
        }
        if (orden.length == 3) break;
        await tester.drag(_lista, const Offset(0, -300));
        await tester.pump();
      }

      expect(orden, ['ATRASADAS', 'PRÓXIMAS', 'SIN FECHA']);
    });

    testWidgets('al 200 % se llega a la última tarjeta sin desbordes', (tester) async {
      await montarPantalla(tester, _entorno(_sesenta()), _ruta, escala: 2);

      await _alFondo(tester);

      expect(find.text('Poner fecha'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'una venta con dos citas entre 30 pendientes: solo sus dos tarjetas dicen el número',
      (tester) async {
        final lista = [
          for (var i = 0; i < 30; i++) pendienteDe('v-$i', lineas: [lineaDe('e-$i', 'p-hijos')]),
          pendienteDe(
            'v-doble',
            fecha: DateTime(2026, 11, 3, 9),
            lineas: [lineaDe('d-1', 'p-hijos')],
          ),
          pendienteDe(
            'v-doble',
            fecha: DateTime(2026, 11, 4, 9),
            lineas: [lineaDe('d-2', 'p-salud')],
          ),
        ];
        await montarPantalla(tester, _entorno(lista), _ruta);

        // Las dos citas de la misma venta son «próximas» y quedan arriba de las 30 sin fecha: solo
        // ellas dicen el número de la venta.
        expect(find.textContaining('Venta 0042'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  });
}

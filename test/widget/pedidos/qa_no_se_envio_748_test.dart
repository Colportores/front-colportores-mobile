// QA de #748 («No se envió»): lo que el implementador no probó. Los casos que documentan un hallazgo van
// con `skip: true` y «QA #748» en el nombre (convención de los [QA-*]); el implementador saca el `skip` al arreglarlo.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pedidos_arnes.dart';
import '../../helpers/pedidos_falsos.dart';
import '../../helpers/qa_no_se_envio_748_estados.dart';

Finder _t(String texto) => find.text(texto, findRichText: true);

void main() {
  group('criterios del issue #748', () {
    testWidgets(
      'dado un pedido rechazado por la fecha, el detalle dice el texto del issue, la acción a mano y '
      'ninguna acción que no se puede',
      (tester) async {
        await montarDetalle(
          tester,
          ArnesDePedidos(pedidos: PedidosFalsos([noSeEnvio748()])),
          'ped-1',
        );
        expect(
          _t(
            'Tu pedido no se envió: la fecha queda fuera de tu campaña. Armalo de nuevo o hablá con '
            'tu coordinador.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('pedidos_boton_principal')), findsOneWidget);
        expect(find.byKey(const Key('pedidos_boton_secundario')), findsNothing);
        expect(find.textContaining('Esperando conexión'), findsNothing);
        expect(find.textContaining('Por autorizar'), findsNothing);
      },
    );

    testWidgets('la tarjeta y la fila de Mi Cuenta se leen completas con un lector de pantalla', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      await montarMisPedidos(
        tester,
        ArnesDePedidos(pedidos: PedidosFalsos([noSeEnvio748()])),
        tamano: telefonoChico748,
        escala: 2,
      );
      final tarjeta = tester.getSemantics(find.byKey(const Key('pedido_ped-1')));
      expect(tarjeta.label, contains('No se envió'));
      expect(tarjeta.label, contains('26 productos'));
      expect(tester.takeException(), isNull);
      manejador.dispose();
    });

    testWidgets(
      'los rechazados y los de otro estado conviven en «Todos», el rechazado primero si es el más nuevo',
      (tester) async {
        await montarMisPedidos(
          tester,
          ArnesDePedidos(
            pedidos: PedidosFalsos([
              noSeEnvio748(),
              pedidoDe(id: 'a', numero: 5, fecha: DateTime(2026, 11, 22, 9)),
            ]),
          ),
        );
        final alto = {
          for (final id in ['ped-1', 'a']) id: tester.getTopLeft(find.byKey(Key('pedido_$id'))).dy,
        };
        expect(alto['ped-1']!, lessThan(alto['a']!));
      },
    );
  });

  group('casos límite', () {
    testWidgets(
      'el rechazo llega y se va varias veces con el detalle abierto: nada queda trabado',
      (tester) async {
        final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe()]));
        await montarDetalle(tester, arnes, 'ped-1');
        for (var i = 0; i < 5; i++) {
          arnes.pedidos.pedidos[0] = noSeEnvio748(fecha: ahoraPedidos);
          arnes.pedidos.cambiar();
          await tester.pump();
          await tester.pump();
          expect(
            find.byKey(const Key('pedidos_boton_secundario')),
            findsNothing,
            reason: 'vuelta $i',
          );
          arnes.pedidos.pedidos[0] = pedidoDe();
          arnes.pedidos.cambiar();
          await tester.pump();
          await tester.pump();
          expect(
            find.byKey(const Key('pedidos_boton_secundario')),
            findsOneWidget,
            reason: 'vuelta $i',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'el pedido rechazado es lo único que hay: «Por autorizar» queda vacío con su mensaje',
      (tester) async {
        await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos([noSeEnvio748()])));
        await tocar(tester, find.byKey(const Key('pedidos_filtro_porAutorizar')));
        expect(find.byKey(const Key('pedido_ped-1')), findsNothing);
        expect(find.byKey(const Key('pedidos_filtro_vacio')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'QA #748: dado el diálogo de «Cancelar pedido» abierto cuando llega el rechazo, confirmar no deja '
      'un aviso que dice que el coordinador ya lo decidió (falso: lo rechazó el servidor)',
      (tester) async {
        final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe()]));
        await montarDetalle(tester, arnes, 'ped-1');
        await tocar(tester, find.byKey(const Key('pedidos_boton_secundario')));
        expect(find.byKey(const Key('pedido_si_cancelar')), findsOneWidget);

        // Mientras la colportora decide, el servidor rechaza el pedido (la cola lo marca INVALID).
        arnes.pedidos.pedidos[0] = noSeEnvio748(fecha: ahoraPedidos);
        arnes.pedidos.cambiar();
        await tester.pump();
        await tester.pump();
        // Lo que devuelve el repositorio real con un pedido «No se envió» (ver el test del implementador).
        arnes.pedidos.fallasAlCancelar.add(const FailurePedidoNoCancelable());
        await tocar(tester, find.byKey(const Key('pedido_si_cancelar')), cuadros: 4);

        expect(find.textContaining('tu coordinador ya lo decidió'), findsNothing);
        expect(find.byKey(const Key('pedidos_boton_principal')), findsOneWidget);
      },
      skip: true,
    );
  });

  group('privacidad', () {
    test('el pedido y su causa no se imprimen con datos: toString no vuelca campos', () {
      final texto = noSeEnvio748().toString();
      expect(texto, isNot(contains('col-1')));
      expect(texto, isNot(contains('ped-1')));
    });
  });
}

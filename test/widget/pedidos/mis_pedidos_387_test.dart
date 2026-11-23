// «Mis pedidos» y el detalle (vista 37B, HU-STK-009, #387): un test por artboard (37B·01 a 37B·06) y los
// casos límite: cancelar (doble toque, falla, confirmar o no), volver a entrar, estados que baja el servidor,
// lista larga y el texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:colportores_mobile/features/pedidos/presentation/textos_pedidos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pedidos_arnes.dart';
import '../../helpers/pedidos_falsos.dart';

Finder _t(String texto) => find.text(texto, findRichText: true);

/// Los tres pedidos del canvas 37B·01: uno de hoy por autorizar, uno despachado y uno recibido.
List<Pedido> _delCanvas() => [
  pedidoDe(id: 'hoy', fecha: DateTime(2026, 11, 23, 9, 30), numero: 231),
  pedidoDe(
    id: 'desp',
    estado: EstadoDelPedido.despachado,
    fecha: DateTime(2026, 10, 15, 12),
    montoCentavos: 480000,
    lineas: const [LineaDelPedido(id: 'x', productoId: 'p-vida', cantidad: 40)],
    montoAutorizadoCentavos: 480000,
    numero: 200,
  ),
  pedidoDe(
    id: 'rec',
    estado: EstadoDelPedido.recibido,
    fecha: DateTime(2026, 10, 2, 12),
    montoCentavos: 3740000,
    lineas: const [LineaDelPedido(id: 'y', productoId: 'p-salud', cantidad: 16)],
    numero: 150,
  ),
];

void main() {
  group('37B·01 · Mis pedidos', () {
    testWidgets(
      'dado que tengo pedidos, los veo con su fecha, monto, estado y cuántos productos, el más '
      'nuevo primero',
      (tester) async {
        await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos(_delCanvas())));

        expect(_t('MI CUENTA'), findsOneWidget);
        expect(_t('Mis pedidos'), findsOneWidget);
        expect(_t(r'HOY · $ 11.840'), findsOneWidget);
        expect(
          _t('Por autorizar'),
          findsNWidgets(2),
          reason: 'el filtro y el estado de la tarjeta',
        );
        expect(_t('26 productos'), findsOneWidget);
        expect(_t(r'15/10 · $ 4.800'), findsOneWidget);
        expect(_t('Despachado'), findsOneWidget);
        expect(_t('40 productos'), findsOneWidget);
        expect(_t(r'02/10 · $ 37.400'), findsOneWidget);
        expect(_t('Recibido'), findsOneWidget);
        expect(_t('+ Nuevo pedido'), findsOneWidget);
        final arriba = tester.getTopLeft(find.byKey(const Key('pedido_hoy'))).dy;
        expect(arriba, lessThan(tester.getTopLeft(find.byKey(const Key('pedido_desp'))).dy));
      },
    );

    testWidgets(
      'dado un filtro, solo deja los pedidos de ese estado; «En camino» junta autorizado y '
      'despachado',
      (tester) async {
        final lista = [
          ..._delCanvas(),
          pedidoDe(id: 'aut', estado: EstadoDelPedido.autorizado, fecha: DateTime(2026, 11, 1)),
          pedidoDe(id: 'canc', estado: EstadoDelPedido.cancelado, fecha: DateTime(2026, 11, 2)),
        ];
        await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos(lista)));
        Finder tarjeta(String id) => find.byKey(Key('pedido_$id'));

        await tocar(tester, find.byKey(const Key('pedidos_filtro_enCamino')));
        expect(tarjeta('desp'), findsOneWidget);
        expect(tarjeta('aut'), findsOneWidget);
        expect(tarjeta('hoy'), findsNothing);

        await tocar(tester, find.byKey(const Key('pedidos_filtro_porAutorizar')));
        expect([tarjeta('hoy').evaluate().length, tarjeta('desp').evaluate().length], [1, 0]);

        await tocar(tester, find.byKey(const Key('pedidos_filtro_recibidos')));
        expect(tarjeta('rec'), findsOneWidget);
        expect(tarjeta('hoy'), findsNothing);

        await tocar(tester, find.byKey(const Key('pedidos_filtro_todos')));
        expect(
          tarjeta('canc'),
          findsOneWidget,
          reason: 'el cancelado no se borra: queda en «Todos»',
        );
        expect(_t('Cancelado'), findsOneWidget);
      },
    );

    testWidgets('dado un filtro sin pedidos, lo dice', (tester) async {
      await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos([_delCanvas().first])));
      await tocar(tester, find.byKey(const Key('pedidos_filtro_recibidos')));
      expect(_t(TextosPedidos.sinPedidosEnElFiltro), findsOneWidget);
    });

    testWidgets('dado un pedido que el coordinador no autorizó, se ve «No autorizado»', (
      tester,
    ) async {
      await montarMisPedidos(
        tester,
        ArnesDePedidos(
          pedidos: PedidosFalsos([pedidoDe(estado: EstadoDelPedido.rechazado, numero: 3)]),
        ),
      );
      expect(_t('No autorizado'), findsOneWidget);
    });

    testWidgets('«+ Nuevo pedido» abre el armado (un solo toque, aunque se toque dos veces)', (
      tester,
    ) async {
      await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos(_delCanvas())));
      await tester.tap(find.text('+ Nuevo pedido'));
      await tester.tap(find.text('+ Nuevo pedido'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_t('Nuevo pedido'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_t('Mis pedidos'), findsOneWidget, reason: 'una sola pantalla encima, no dos');
    });

    testWidgets('al volver de un detalle y reentrar, la lista sigue ahí', (tester) async {
      await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos(_delCanvas())));
      await tocar(tester, find.byKey(const Key('pedido_hoy')), cuadros: 8);
      expect(_t('PEDIDO DE HOY'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pedido_hoy')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('pedido_hoy')), cuadros: 8);
      expect(_t('PEDIDO DE HOY'), findsOneWidget);
    });
  });

  group('37B·04 · Sin pedidos', () {
    testWidgets('dado que no pedí nada, lo dice y ofrece armar uno', (tester) async {
      await montarMisPedidos(tester, ArnesDePedidos());
      expect(_t('Todavía no pediste nada'), findsOneWidget);
      expect(_t('Armá un pedido y tu coordinador lo autoriza.'), findsOneWidget);
      expect(_t('+ Nuevo pedido'), findsOneWidget);
    });
  });

  group('37B·05 · Cargando', () {
    testWidgets(
      'dado que todavía se leen, veo los bloques grises y el lector de pantalla lo dice',
      (tester) async {
        final arnes = ArnesDePedidos(pedidos: PedidosFalsos(_delCanvas()));
        arnes.pedidos.esperaLectura = Completer<void>();
        await montarMisPedidos(tester, arnes);
        expect(find.byKey(const Key('pedidos_esqueleto')), findsOneWidget);
        expect(find.bySemanticsLabel(TextosPedidos.cargando), findsOneWidget);
        arnes.pedidos.esperaLectura!.complete();
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('pedidos_esqueleto')), findsNothing);
        expect(find.byKey(const Key('pedido_hoy')), findsOneWidget);
      },
    );
  });

  group('37B·06 · Error', () {
    testWidgets('dado que no se pudieron leer, veo el error y «Reintentar» los trae', (
      tester,
    ) async {
      final arnes = ArnesDePedidos(pedidos: PedidosFalsos(_delCanvas()));
      arnes.pedidos.fallaAlLeer = true;
      await montarMisPedidos(tester, arnes);
      expect(_t('No pudimos traer tus pedidos.'), findsOneWidget);
      expect(find.byKey(const Key('pedido_hoy')), findsNothing);

      arnes.pedidos.fallaAlLeer = false;
      await tocar(tester, find.byKey(const Key('pedidos_aviso_boton')), cuadros: 4);
      expect(_t('No pudimos traer tus pedidos.'), findsNothing);
      expect(find.byKey(const Key('pedido_hoy')), findsOneWidget);
    });
  });

  group('37B·02 · Detalle: por autorizar', () {
    testWidgets(
      'dado un pedido por autorizar, veo su monto, cuándo se envió, lo que lleva y «Cancelar '
      'pedido»',
      (tester) async {
        await montarDetalle(tester, ArnesDePedidos(pedidos: PedidosFalsos(_delCanvas())), 'hoy');
        expect(_t('PEDIDO DE HOY'), findsOneWidget);
        expect(_t(r'$ 11.840'), findsOneWidget);
        expect(_t('Por autorizar · enviado hoy 09:30'), findsOneWidget);
        expect(_t('Salud y Hogar'), findsOneWidget);
        expect(_t('× 4'), findsOneWidget);
        expect(_t('Nuestros Hijos'), findsOneWidget);
        expect(_t('× 2'), findsOneWidget);
        expect(_t('Vida Feliz'), findsOneWidget);
        expect(_t('× 20'), findsOneWidget);
        expect(_t('Cancelar pedido'), findsOneWidget);
        expect(find.textContaining('límite'), findsNothing);
      },
    );

    testWidgets('dado un pedido que pasaba el límite, el detalle lo recuerda', (tester) async {
      await montarDetalle(
        tester,
        ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(excedeLimite: true, numero: 1)])),
        'ped-1',
      );
      expect(
        _t('Lo enviaste pasando el límite de deuda. Tu coordinador lo va a tener en cuenta.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'dado un pedido que todavía no llegó (sin conexión), dice «guardado» y no «enviado»',
      (tester) async {
        await montarDetalle(
          tester,
          ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(fecha: DateTime(2026, 11, 23, 9, 30))])),
          'ped-1',
        );
        expect(_t('Por autorizar · guardado hoy 09:30'), findsOneWidget);
      },
    );

    testWidgets('dado un pedido de otro día, el título y la línea dicen la fecha', (tester) async {
      await montarDetalle(
        tester,
        ArnesDePedidos(
          pedidos: PedidosFalsos([pedidoDe(fecha: DateTime(2026, 10, 20, 8), numero: 4)]),
        ),
        'ped-1',
      );
      expect(_t('PEDIDO DEL 20/10'), findsOneWidget);
      expect(_t('Por autorizar · enviado el 20/10'), findsOneWidget);
    });

    testWidgets('dado un producto que ya no está en el catálogo, la línea dice «Producto»', (
      tester,
    ) async {
      await montarDetalle(
        tester,
        ArnesDePedidos(
          pedidos: PedidosFalsos([
            pedidoDe(
              lineas: const [LineaDelPedido(id: 'z', productoId: 'p-viejo', cantidad: 3)],
            ),
          ]),
        ),
        'ped-1',
      );
      expect(_t('Producto'), findsOneWidget);
      expect(_t('× 3'), findsOneWidget);
    });
  });

  group('Cancelar el pedido', () {
    testWidgets(
      'dado que cancelo y confirmo, el pedido queda «Cancelado», no se borra y ya no se puede '
      'cancelar',
      (tester) async {
        final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(numero: 1)]));
        await montarDetalle(tester, arnes, 'ped-1');
        await tocar(tester, find.text('Cancelar pedido'));
        expect(_t('¿Cancelar este pedido?'), findsOneWidget);
        await tocar(tester, find.byKey(const Key('pedido_si_cancelar')), cuadros: 6);

        expect(arnes.pedidos.cancelados, ['ped-1']);
        expect(_t('Cancelado'), findsOneWidget);
        expect(_t('Cancelaste este pedido. Ya no le llega a tu coordinador.'), findsOneWidget);
        expect(find.text('Cancelar pedido'), findsNothing);
        expect(arnes.pedidos.pedidos, hasLength(1));
      },
    );

    testWidgets('dado que me arrepiento («No, dejarlo»), no se cancela nada', (tester) async {
      final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(numero: 1)]));
      await montarDetalle(tester, arnes, 'ped-1');
      await tocar(tester, find.text('Cancelar pedido'));
      await tocar(tester, find.byKey(const Key('pedido_no_cancelar')), cuadros: 6);
      expect(arnes.pedidos.llamadasACancelar, 0);
      expect(_t('Por autorizar · enviado hoy 10:00'), findsNothing);
      expect(find.text('Cancelar pedido'), findsOneWidget);
    });

    testWidgets(
      'dado que la cancelación falla, veo el aviso, el pedido sigue por autorizar y el botón '
      'vuelve a habilitarse',
      (tester) async {
        final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(numero: 1)]));
        arnes.pedidos.fallasAlCancelar.add(const FailurePedidoNoCancelado(causa: 'X'));
        await montarDetalle(tester, arnes, 'ped-1');
        await tocar(tester, find.text('Cancelar pedido'));
        await tocar(tester, find.byKey(const Key('pedido_si_cancelar')), cuadros: 6);

        expect(
          _t('No pudimos cancelar el pedido. Sigue por autorizar: probá de nuevo.'),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        final boton = tester.widget<OutlinedButton>(
          find.byKey(const Key('pedidos_boton_secundario')),
        );
        expect(boton.onPressed, isNotNull);

        // Reintento: sale bien y el aviso se va.
        await tocar(tester, find.text('Cancelar pedido'));
        await tocar(tester, find.byKey(const Key('pedido_si_cancelar')), cuadros: 6);
        expect(_t('Cancelado'), findsOneWidget);
        expect(find.textContaining('No pudimos cancelar'), findsNothing);
      },
    );

    testWidgets('dado que el coordinador ya lo decidió mientras tanto, dice que ya no se puede', (
      tester,
    ) async {
      final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(numero: 1)]));
      arnes.pedidos.fallasAlCancelar.add(const FailurePedidoNoCancelable());
      await montarDetalle(tester, arnes, 'ped-1');
      await tocar(tester, find.text('Cancelar pedido'));
      await tocar(tester, find.byKey(const Key('pedido_si_cancelar')), cuadros: 6);
      expect(
        _t('Este pedido ya no se puede cancelar: tu coordinador ya lo decidió.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'dado un doble toque en «Sí, cancelar» con la cancelación en vuelo, se cancela UNA vez',
      (tester) async {
        final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(numero: 1)]));
        arnes.pedidos.esperaAlCancelar = Completer<void>();
        await montarDetalle(tester, arnes, 'ped-1');
        await tocar(tester, find.text('Cancelar pedido'));
        await tocar(tester, find.byKey(const Key('pedido_si_cancelar')), cuadros: 8);
        expect(_t('Cancelando…'), findsOneWidget);
        // Con la cancelación en vuelo, el botón está apagado: un segundo toque no hace nada.
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(const Key('pedidos_boton_secundario')))
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const Key('pedidos_boton_secundario')), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 500));
        expect(arnes.pedidos.llamadasACancelar, 1);
        arnes.pedidos.esperaAlCancelar!.complete();
        await tester.pump();
        await tester.pump();
        expect(arnes.pedidos.llamadasACancelar, 1);
        expect(_t('Cancelado'), findsOneWidget);
      },
    );
  });

  group('37B·03 · No autorizado', () {
    testWidgets(
      'dado un pedido que mi coordinador no autorizó, veo su motivo y «Armar uno nuevo»',
      (tester) async {
        final arnes = ArnesDePedidos(
          pedidos: PedidosFalsos([
            pedidoDe(
              estado: EstadoDelPedido.rechazado,
              fecha: DateTime(2026, 10, 20, 12),
              montoCentavos: 2196000,
              motivoRechazo: 'Depositá lo que tenés en mano y pedí de nuevo',
              numero: 9,
            ),
          ]),
        );
        await montarDetalle(tester, arnes, 'ped-1');
        expect(_t('PEDIDO DEL 20/10'), findsOneWidget);
        expect(_t(r'$ 21.960'), findsOneWidget);
        expect(_t('No autorizado'), findsOneWidget);
        expect(
          _t('Tu coordinador no lo autorizó: «Depositá lo que tenés en mano y pedí de nuevo».'),
          findsOneWidget,
        );
        expect(find.text('Cancelar pedido'), findsNothing);

        await tocar(tester, find.text('Armar uno nuevo'), cuadros: 8);
        expect(_t('Nuevo pedido'), findsOneWidget);
      },
    );

    testWidgets('dado un rechazo sin motivo, el aviso dice qué hacer igual', (tester) async {
      await montarDetalle(
        tester,
        ArnesDePedidos(
          pedidos: PedidosFalsos([pedidoDe(estado: EstadoDelPedido.rechazado, numero: 9)]),
        ),
        'ped-1',
      );
      expect(
        _t('Tu coordinador no lo autorizó. Hablá con él y armá un pedido nuevo si hace falta.'),
        findsOneWidget,
      );
    });
  });

  group('Estados que baja el servidor', () {
    testWidgets(
      'dado un pedido autorizado con una línea reducida, veo lo autorizado y lo que pedí, y lo '
      'autorizado en el monto',
      (tester) async {
        await montarDetalle(
          tester,
          ArnesDePedidos(
            pedidos: PedidosFalsos([
              pedidoDe(
                estado: EstadoDelPedido.autorizado,
                montoAutorizadoCentavos: 900000,
                numero: 2,
                lineas: const [
                  LineaDelPedido(
                    id: 'a',
                    productoId: 'p-salud',
                    cantidad: 4,
                    cantidadAutorizada: 3,
                  ),
                  LineaDelPedido(id: 'b', productoId: 'p-hijos', cantidad: 2),
                ],
              ),
            ]),
          ),
          'ped-1',
        );
        expect(_t(r'$ 9.000'), findsOneWidget);
        expect(_t('Autorizado'), findsOneWidget);
        expect(_t('× 3 (pediste 4)'), findsOneWidget);
        expect(_t('× 2'), findsOneWidget);
        expect(
          find.text('Cancelar pedido'),
          findsNothing,
          reason: 'autorizado: lo cancela el coordinador',
        );
      },
    );

    testWidgets('dado un pedido despachado o recibido, es solo lectura', (tester) async {
      for (final estado in [EstadoDelPedido.despachado, EstadoDelPedido.recibido]) {
        await montarDetalle(
          tester,
          ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(estado: estado, numero: 2)])),
          'ped-1',
        );
        expect(_t(TextosPedidos.estado(estado)), findsOneWidget, reason: estado.name);
        expect(find.byKey(const Key('pedidos_boton_secundario')), findsNothing);
        expect(find.byKey(const Key('pedidos_boton_principal')), findsNothing);
      }
    });

    testWidgets(
      'dado que el servidor cambia el estado con el detalle abierto, el detalle se actualiza',
      (tester) async {
        final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(numero: 1)]));
        await montarDetalle(tester, arnes, 'ped-1');
        expect(find.text('Cancelar pedido'), findsOneWidget);
        arnes.pedidos.pedidos[0] = pedidoDe(estado: EstadoDelPedido.autorizado, numero: 1);
        arnes.pedidos.cambiar();
        await tester.pump();
        await tester.pump();
        expect(_t('Autorizado'), findsOneWidget);
        expect(find.text('Cancelar pedido'), findsNothing);
      },
    );

    testWidgets('dado un pedido que no está en el teléfono, lo dice', (tester) async {
      await montarDetalle(tester, ArnesDePedidos(), 'no-existe');
      expect(_t(TextosPedidos.pedidoNoEncontrado), findsOneWidget);
    });
  });

  group('Datos límite', () {
    testWidgets('dada una lista larga de pedidos, se desplaza y todos se pueden abrir', (
      tester,
    ) async {
      final muchos = [
        for (var i = 0; i < 80; i++)
          pedidoDe(
            id: 'p$i',
            fecha: DateTime(2026, 9, 1).add(Duration(days: i)),
            estado: EstadoDelPedido.recibido,
          ),
      ];
      await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos(muchos)));
      await tester.scrollUntilVisible(
        find.byKey(const Key('pedido_p0')),
        300,
        scrollable: find.descendant(
          of: find.byKey(const Key('pedidos_lista')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.byKey(const Key('pedido_p0')), findsOneWidget);
    });

    for (final (nombre, tamano) in [
      ('360×640', const Size(360, 640)),
      ('320×568', const Size(320, 568)),
    ]) {
      testWidgets(
        'con el texto al 200 % a $nombre, la lista y el detalle (con motivo largo) no desbordan',
        (tester) async {
          final arnes = ArnesDePedidos(
            pedidos: PedidosFalsos([
              pedidoDe(
                id: 'r',
                estado: EstadoDelPedido.rechazado,
                montoCentavos: 987654321,
                motivoRechazo:
                    'Un motivo bastante largo de tu coordinador ${'que sigue y sigue ' * 6}',
                numero: 1,
              ),
            ]),
          );
          await montarMisPedidos(tester, arnes, tamano: tamano, escala: 2);
          expect(tester.takeException(), isNull);
          await tocar(tester, find.byKey(const Key('pedido_r')), cuadros: 8);
          expect(tester.takeException(), isNull);
          expect(
            find.textContaining('Un motivo bastante largo', skipOffstage: false),
            findsOneWidget,
          );
        },
      );
    }
  });
}

// «Cargar de nuevo» del ticket rechazado de un cobro con tarjeta (#728, regla R7 del 23/11): el detalle
// de «Mis tickets» (38B·02) abre la foto del ticket (vista 29 C) con ese cobro precargado. Casos límite:
// doble toque, falla al leer el cobro (el botón vuelve a servir), cerrar la cámara sin sacar nada y
// volver a entrar, el ticket que se rehace desde otra pantalla y letra al 200 %.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/presentation/pages/historial_de_tickets_page.dart';
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:colportores_mobile/features/tickets/presentation/textos_tickets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/historial_tickets_arnes.dart';
import '../../helpers/ticket_tarjeta_arnes.dart';

Finder _texto(String t) => find.text(t, findRichText: true);

final _botonCargarDeNuevo = find.byKey(const Key('ticket_cargar_de_nuevo'));

/// El ticket rechazado de un cobro con tarjeta de $ 1.200 (cobro `cobro-c1`).
ItemDelHistorial _rechazado({String? cobroId}) => itemDePrueba(
  'c1',
  pesos: 1200,
  lugar: LugarDelTicket.cobroConTarjeta,
  concepto: null,
  estado: EstadoDelItem.rechazado,
  motivo: 'No se lee el número',
  autorizacion: '004512',
  tarjeta: TipoDeTarjeta.credito,
  cobroId: cobroId,
);

class _Escena {
  _Escena(this.repo, this.ticket);
  final HistorialControlable repo;
  final ArnesTicket ticket;
}

/// Monta «Mis tickets» con [items], el cobro `cobro-c1` vivo si [conCobro], y abre el detalle de `c1`.
Future<_Escena> _abrirDetalle(
  WidgetTester tester, {
  List<ItemDelHistorial>? items,
  bool conCobro = true,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  final repo = HistorialControlable(inicial: historialCon(items ?? [_rechazado()]));
  if (conCobro) repo.cobros['cobro-c1'] = cobroConTarjeta(id: 'cobro-c1');
  final ticket = nuevoArnesTicket();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesDeTicket(ticket),
        historialDeTicketsRepositoryProvider.overrideWithValue(repo),
        visorDeFotosDeTicketProvider.overrideWithValue(VisorGuionado()),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_historial'),
                onPressed: () => HistorialDeTicketsPage.abrir(context, colportorId: 'col-1'),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await abrirHistorial(tester);
  await tester.scrollUntilVisible(
    fila('c1'),
    100,
    scrollable: find
        .descendant(of: find.byKey(const Key('tickets_lista')), matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(fila('c1'));
  await tester.pump();
  await tester.tapAt(tester.getTopLeft(fila('c1')) + const Offset(30, 30));
  await tester.pumpAndSettle();
  return _Escena(repo, ticket);
}

void main() {
  group('38B·02 · «Cargar de nuevo» de un cobro con tarjeta', () {
    testWidgets('el detalle del ticket rechazado ofrece «Cargar de nuevo»', (tester) async {
      await _abrirDetalle(tester);

      expect(
        _texto('Tu coordinador lo rechazó: «No se lee el número». No se acreditó.'),
        findsOneWidget,
      );
      expect(_botonCargarDeNuevo, findsOneWidget);
      expect(find.byKey(const Key('ticket_aviso_cobro')), findsNothing);
    });

    testWidgets('abre la foto del ticket con el cobro precargado, sin pedir persona ni venta', (
      tester,
    ) async {
      await _abrirDetalle(tester);

      await tester.tap(_botonCargarDeNuevo);
      await tester.pumpAndSettle();

      expect(paginaTicket, findsOneWidget);
      expect(find.byKey(const Key('ticket_sacar_foto')), findsOneWidget);
      expect(
        find.byKey(const Key('ticket_detalle')),
        findsNothing,
        reason: 'el detalle quedó atrás',
      );
    });

    testWidgets('con la foto nueva se registra otro ticket ligado al mismo cobro, con sus datos', (
      tester,
    ) async {
      final e = await _abrirDetalle(tester);
      await tester.tap(_botonCargarDeNuevo);
      await tester.pumpAndSettle();

      await enviarElTicket(tester);

      final nuevo = e.ticket.repo.recibidos.single;
      expect(nuevo.cobroId, 'cobro-c1');
      expect(nuevo.ticket.tipo, TipoDeTicket.cobroTarjeta);
      expect(nuevo.ticket.montoCentavos, 120000, reason: 'el monto del cobro');
      expect(
        nuevo.ticket.numeroAutorizacion,
        '004512',
        reason: 'la aprobación que guardó el cobro',
      );
      expect(nuevo.ticket.tarjetaTipo, TipoDeTarjeta.credito);
      expect(nuevo.ticket.tarjetaMarca, 'Visa');
      expect(nuevo.ticket.id, isNot('t-c1'), reason: 'es un ticket nuevo: el rechazado queda');
    });

    testWidgets('cargado el ticket nuevo, «Listo» vuelve a la lista de «Mis tickets»', (
      tester,
    ) async {
      await _abrirDetalle(tester);
      await tester.tap(_botonCargarDeNuevo);
      await tester.pumpAndSettle();
      await enviarElTicket(tester);

      await tocarTicket(tester, find.byKey(const Key('ticket_listo')));

      expect(find.byKey(const Key('tickets_lista')), findsOneWidget);
      expect(find.byKey(const Key('ticket_detalle')), findsNothing);
      expect(paginaTicket, findsNothing);
    });
  });

  group('casos límite', () {
    testWidgets('un doble toque abre una sola foto del ticket y lee el cobro una vez', (
      tester,
    ) async {
      final e = await _abrirDetalle(tester);

      await tester.tap(_botonCargarDeNuevo);
      await tester.tap(_botonCargarDeNuevo, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(paginaTicket, findsOneWidget);
      expect(e.repo.cobrosPedidos, 1);
      await tester.tap(atrasTicket);
      await tester.pumpAndSettle();
      expect(paginaTicket, findsNothing, reason: 'no había otra pantalla debajo');
      expect(find.byKey(const Key('ticket_detalle')), findsOneWidget);
    });

    testWidgets('si falla la lectura del cobro lo dice y el botón vuelve a servir', (tester) async {
      final e = await _abrirDetalle(tester);
      e.repo.fallaAlLeerElCobro = StateError('sin base');

      await tester.tap(_botonCargarDeNuevo);
      await tester.pumpAndSettle();

      expect(paginaTicket, findsNothing);
      expect(find.byKey(const Key('ticket_aviso_cobro')), findsOneWidget);
      expect(_texto(TextosTickets.cobroNoSePudoAbrir), findsOneWidget);
      expect(_botonCargarDeNuevo, findsOneWidget);

      await tester.tap(_botonCargarDeNuevo);
      await tester.pumpAndSettle();

      expect(paginaTicket, findsOneWidget, reason: 'el segundo intento sí abre');
      await tester.tap(atrasTicket);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ticket_aviso_cobro')), findsNothing, reason: 'el aviso se fue');
    });

    testWidgets('si el cobro ya no está vivo lo dice, no inventa uno y no se traba', (
      tester,
    ) async {
      final e = await _abrirDetalle(tester, conCobro: false);

      await tester.tap(_botonCargarDeNuevo);
      await tester.pumpAndSettle();

      expect(e.repo.cobrosPedidos, 1);
      expect(paginaTicket, findsNothing);
      expect(_texto(TextosTickets.cobroNoSePudoAbrir), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(of: _botonCargarDeNuevo, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNotNull,
        reason: 'el botón sigue habilitado',
      );
    });

    testWidgets('cerrar la cámara sin sacar nada vuelve al detalle y se puede reabrir', (
      tester,
    ) async {
      await _abrirDetalle(tester);
      await tester.tap(_botonCargarDeNuevo);
      await tester.pumpAndSettle();

      await tester.tap(atrasTicket);
      await tester.pumpAndSettle();

      expect(paginaTicket, findsNothing);
      expect(find.byKey(const Key('ticket_detalle')), findsOneWidget);
      expect(_botonCargarDeNuevo, findsOneWidget);

      await tester.tap(_botonCargarDeNuevo);
      await tester.pumpAndSettle();
      expect(paginaTicket, findsOneWidget);
    });

    testWidgets('el ticket rechazado cuyo cobro ya tiene otro ticket no ofrece «Cargar de nuevo»', (
      tester,
    ) async {
      await _abrirDetalle(tester, items: [_rechazado(cobroId: '')]);

      expect(
        _texto('Tu coordinador lo rechazó: «No se lee el número». No se acreditó.'),
        findsOneWidget,
      );
      expect(_botonCargarDeNuevo, findsNothing);
    });

    testWidgets('si el cobro se liga a un ticket nuevo con el detalle abierto, el botón se va', (
      tester,
    ) async {
      final e = await _abrirDetalle(tester);
      expect(_botonCargarDeNuevo, findsOneWidget);

      e.repo.emitir(historialCon([_rechazado(cobroId: '')]));
      await tester.pumpAndSettle();

      expect(_botonCargarDeNuevo, findsNothing);
      expect(
        _texto('Tu coordinador lo rechazó: «No se lee el número». No se acreditó.'),
        findsOneWidget,
      );
    });

    testWidgets('con letra al 200 % en 320×568 el botón se ve y abre la foto del ticket', (
      tester,
    ) async {
      await _abrirDetalle(tester, tamano: const Size(320, 568), escala: 2);

      expect(_botonCargarDeNuevo, findsOneWidget);
      await tester.tap(_botonCargarDeNuevo);
      await tester.pumpAndSettle();

      expect(paginaTicket, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

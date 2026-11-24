// Arnés del QA de «Cargar de nuevo» del ticket rechazado de un cobro con tarjeta (#728, vista 38B·02 →
// 29 C): el detalle montado a un tamaño y a una escala dados, los estados a los que una persona llega y
// un historial cuya lectura del cobro se queda esperando.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/repositories/historial_de_tickets_repository.dart';
import 'package:colportores_mobile/features/tickets/presentation/pages/historial_de_tickets_page.dart';
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_vista33_deposito_443_arnes.dart' show cargarFuentes443;
import 'qa_vista38_388_arnes.dart';
import 'ticket_tarjeta_arnes.dart';

Finder texto728(String t) => find.text(t, findRichText: true);

final boton728 = find.byKey(const Key('ticket_cargar_de_nuevo'));
final avisoCobro728 = find.byKey(const Key('ticket_aviso_cobro'));
final lista728 = find.byKey(const Key('ticket_detalle_lista'));

const motivoLargo728 =
    'La foto salió movida y no se alcanza a leer ni el número de aprobación ni los últimos cuatro '
    'dígitos de la tarjeta; sacala de nuevo con más luz, sin reflejos y con el ticket plano.';

ItemDelHistorial rechazado728({
  String? cobroId,
  String? motivo = 'No se lee el número',
  EstadoDelItem estado = EstadoDelItem.rechazado,
  TipoDeTarjeta? tarjeta = TipoDeTarjeta.credito,
}) => itemDePrueba(
  'c1',
  pesos: 1200,
  lugar: LugarDelTicket.cobroConTarjeta,
  concepto: null,
  estado: estado,
  motivo: motivo,
  autorizacion: '004512',
  tarjeta: tarjeta,
  cobroId: cobroId,
);

/// Un historial cuya lectura del cobro queda esperando hasta que el test la suelta.
final class RepoLento728 implements HistorialDeTicketsRepository {
  RepoLento728(this.base);
  final HistorialControlable base;
  final espera = Completer<Cobranza?>();
  var pedidos = 0;

  @override
  Stream<HistorialDeTickets> observar() => base.observar();

  @override
  Future<Cobranza?> cobroConTarjeta(String cobroId) {
    pedidos++;
    return espera.future;
  }
}

typedef Escena728 = ({HistorialControlable repo, ArnesTicket ticket});

/// Monta «Mis tickets» con [items] (por defecto el rechazado de un cobro con tarjeta) y abre el
/// detalle de `c1`.
Future<Escena728> abrirDetalle728(
  WidgetTester tester, {
  List<ItemDelHistorial>? items,
  bool conCobro = true,
  Size tamano = t360x640,
  double escala = 1,
  String id = 'c1',
  HistorialDeTicketsRepository Function(HistorialControlable)? envolver,
}) async {
  await cargarFuentes443(tester);
  final repo = HistorialControlable(inicial: historialCon(items ?? [rechazado728()]));
  if (conCobro) repo.cobros['cobro-c1'] = cobroConTarjeta(id: 'cobro-c1');
  final ticket = nuevoArnesTicket();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesDeTicket(ticket),
        historialDeTicketsRepositoryProvider.overrideWithValue(
          envolver == null ? repo : envolver(repo),
        ),
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
    fila(id),
    100,
    scrollable: find
        .descendant(of: find.byKey(const Key('tickets_lista')), matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(fila(id));
  await tester.pump();
  await tester.tapAt(tester.getTopLeft(fila(id)) + const Offset(30, 30));
  await tester.pumpAndSettle();
  return (repo: repo, ticket: ticket);
}

Future<void> tocarCargarDeNuevo728(WidgetTester tester) async {
  await tester.tap(boton728);
  await tester.pumpAndSettle();
}

enum Estado728 { detalle, motivoLargo, sinMotivo, avisoFalla, avisoNoVivo, fotoDelTicket }

Future<Escena728> llegarA728(
  WidgetTester tester,
  Estado728 estado, {
  required Size tamano,
  required double escala,
}) async {
  final motivo = switch (estado) {
    Estado728.motivoLargo => motivoLargo728,
    Estado728.sinMotivo => null,
    _ => 'No se lee el número',
  };
  final e = await abrirDetalle728(
    tester,
    items: [rechazado728(motivo: motivo)],
    conCobro: estado != Estado728.avisoNoVivo,
    tamano: tamano,
    escala: escala,
  );
  switch (estado) {
    case Estado728.avisoFalla:
      e.repo.fallaAlLeerElCobro = StateError('sin base');
      await tocarCargarDeNuevo728(tester);
    case Estado728.avisoNoVivo:
      await tocarCargarDeNuevo728(tester);
    case Estado728.fotoDelTicket:
      await tocarCargarDeNuevo728(tester);
    case Estado728.detalle || Estado728.motivoLargo || Estado728.sinMotivo:
      break;
  }
  return e;
}

Rect rectDe728(WidgetTester tester, Finder f) => tester.getRect(f);

/// ¿El [f] se ve entero dentro del área que se desplaza de la pantalla?
bool seVeEnLaLista728(WidgetTester tester, Finder f) {
  final r = rectDe728(tester, f);
  final area = rectDe728(tester, lista728);
  return r.top >= area.top - 0.5 && r.bottom <= area.bottom + 0.5;
}

bool botonHabilitado728(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.descendant(of: boton728, matching: find.byType(FilledButton)))
        .onPressed !=
    null;

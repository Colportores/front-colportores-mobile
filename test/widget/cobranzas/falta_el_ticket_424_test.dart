// «Falta el ticket» en el detalle del cobro (vista 30 B, #424; decisión P4 de #169 y precisión de la P6
// de #427): un cobro con tarjeta vivo y sin ticket muestra la marca con «Sacar foto del ticket», que abre
// la foto del ticket (vista 29 C) con ese cobro. Casos límite: doble toque, cerrar la cámara sin sacar
// nada (la marca sigue), ticket guardado (la marca se va), falla al leer al volver, volver y reentrar,
// y letra al 200 % a 320 de ancho.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/detalle_del_cobro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/anular_cobro_arnes.dart';
import '../../helpers/ticket_tarjeta_arnes.dart';

final _marca = find.byKey(const Key('detalle_cobro_falta_ticket'));
final _sacarFoto = find.text('Sacar foto del ticket');
final _atrasDelTicket = find.descendant(
  of: paginaTicket,
  matching: find.byKey(const Key('venta_atras')),
);

DetalleDelCobro _tarjeta({String? ticketId, DateTime? anuladoAt, DateTime? fecha}) =>
    detalleDeEjemplo(
      medio: MedioCobranza.tarjeta,
      ticketId: ticketId,
      numeroAprobacion: '004512',
      anuladoAt: anuladoAt,
      motivo: anuladoAt == null ? null : MotivoDeAnulacion.montoEquivocado,
      fecha: fecha,
    );

Future<({ArnesAnular detalle, ArnesTicket ticket})> _montar(
  WidgetTester tester, {
  AnulacionesEnMemoria? repo,
  bool conCamara = true,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final ticket = nuevoArnesTicket();
  final detalle = await montarDetalleDelCobro(
    tester,
    repo: repo ?? AnulacionesEnMemoria(cobros: [_tarjeta()]),
    overrides: overridesDeTicket(ticket, conCamara: conCamara),
    escala: escala,
    tamano: tamano,
    abrir: abrir,
  );
  return (detalle: detalle, ticket: ticket);
}

void main() {
  group('Falta el ticket · la marca', () {
    testWidgets('dado un cobro con tarjeta sin ticket, entonces muestra la marca y la acción', (
      tester,
    ) async {
      await _montar(tester);

      expect(_marca, findsOneWidget);
      expect(
        find.textContaining('Falta el ticket. Guardá el ticket de la tarjeta', findRichText: true),
        findsOneWidget,
      );
      expect(_sacarFoto, findsOneWidget);
      // Sigue pudiendo anular: la marca no reemplaza nada del detalle.
      expect(botonAnularDelDetalle, findsOneWidget);
    });

    testWidgets('con el ticket ya cargado no hay marca', (tester) async {
      await _montar(
        tester,
        repo: AnulacionesEnMemoria(cobros: [_tarjeta(ticketId: 'tk-1')]),
      );

      expect(paginaDetalle, findsOneWidget);
      expect(_marca, findsNothing);
      expect(_sacarFoto, findsNothing);
    });

    testWidgets('un cobro en efectivo no lleva marca', (tester) async {
      await _montar(tester, repo: AnulacionesEnMemoria());

      expect(paginaDetalle, findsOneWidget);
      expect(_marca, findsNothing);
    });

    testWidgets('un cobro con tarjeta anulado no pide el ticket', (tester) async {
      await _montar(
        tester,
        repo: AnulacionesEnMemoria(
          cobros: [_tarjeta(anuladoAt: DateTime.utc(2026, 10, 23, 17, 30))],
        ),
      );

      expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
      expect(_marca, findsNothing);
    });

    testWidgets('pasadas las 72 h la marca sigue: el ticket se sigue necesitando', (tester) async {
      await _montar(
        tester,
        repo: AnulacionesEnMemoria(cobros: [_tarjeta(fecha: DateTime.utc(2026, 10, 18, 12))]),
      );

      expect(find.text('Anular cobro'), findsNothing);
      expect(_marca, findsOneWidget);
      expect(_sacarFoto, findsOneWidget);
    });

    testWidgets('sin cámara la marca avisa pero no ofrece una acción que no anda', (tester) async {
      await _montar(tester, conCamara: false);

      expect(_marca, findsOneWidget);
      expect(_sacarFoto, findsNothing);
    });
  });

  group('Falta el ticket · «Sacar foto del ticket»', () {
    testWidgets('abre la foto del ticket con ese cobro y la cámara cerrada deja la marca', (
      tester,
    ) async {
      final a = await _montar(tester);

      await tocar(tester, _sacarFoto);
      expect(paginaTicket, findsOneWidget);
      // Es el cobro del detalle: la foto del ticket llega con su monto y su número de aprobación.
      await irALosDatos(tester);
      expect(tester.widget<TextField>(campoMontoTicket).controller!.text, '600');
      expect(tester.widget<TextField>(campoAutorizacion).controller!.text, '004512');

      // Atrás hasta salir de la foto del ticket, sin enviar nada.
      for (var i = 0; i < 5 && paginaTicket.evaluate().isNotEmpty; i++) {
        await tocar(tester, _atrasDelTicket);
      }

      expect(paginaTicket, findsNothing);
      expect(paginaDetalle, findsOneWidget);
      expect(_marca, findsOneWidget);
      expect(a.ticket.repo.recibidos, isEmpty);
      expect(a.detalle.repo.lecturas, 2);
      expect(a.detalle.resultados, isEmpty);
    });

    testWidgets('con el ticket guardado, «Listo» vuelve y la marca desaparece', (tester) async {
      final a = await _montar(tester);

      await tocar(tester, _sacarFoto);
      await enviarElTicket(tester);

      expect(a.ticket.repo.recibidos.single.cobroId, 'c-1');
      // Lo que hace `RegistrarTicketUseCase`: liga el cobro con el ticket (`cobranza.ticket_id`).
      a.detalle.repo.detalles['c-1'] = _tarjeta(ticketId: a.ticket.repo.recibidos.single.ticket.id);
      await tocarTicket(tester, find.byKey(const Key('ticket_listo')));

      expect(paginaTicket, findsNothing);
      expect(paginaDetalle, findsOneWidget);
      expect(_marca, findsNothing);
      expect(_sacarFoto, findsNothing);
    });

    testWidgets('doble toque: abre una sola vez la foto del ticket', (tester) async {
      await _montar(tester);
      await traerAlAlcance(tester, _sacarFoto);

      await tester.tap(_sacarFoto);
      await tester.tap(_sacarFoto, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(paginaTicket, findsOneWidget);
      await tocar(tester, _atrasDelTicket);

      // Una sola pantalla encima: al volver está el detalle, no otra foto del ticket.
      expect(paginaTicket, findsNothing);
      expect(paginaDetalle, findsOneWidget);
    });

    testWidgets('falla al leer el cobro al volver: «Reintentar» lo recupera con la marca', (
      tester,
    ) async {
      final a = await _montar(tester);

      await tocar(tester, _sacarFoto);
      a.detalle.repo
        ..fallaDeLectura = const FailureCobroNoAnulado()
        ..fallaDeLecturaUnaVez = true;
      await tocar(tester, _atrasDelTicket);

      expect(find.byKey(const Key('detalle_cobro_error_lectura')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('venta_aviso_accion')));

      expect(find.byKey(const Key('detalle_cobro_error_lectura')), findsNothing);
      expect(_marca, findsOneWidget);
      // Y el botón vuelve a servir: no quedó nada «ocupado».
      await tocar(tester, _sacarFoto);
      expect(paginaTicket, findsOneWidget);
    });

    testWidgets('volver atrás y reentrar: la marca sigue y la acción abre de nuevo', (
      tester,
    ) async {
      final a = await _montar(tester);

      await tocar(tester, find.byKey(const Key('venta_atras')));
      expect(paginaDetalle, findsNothing);
      expect(a.detalle.resultados, [false]);

      await abrirDetalle(tester);
      expect(_marca, findsOneWidget);
      await tocar(tester, _sacarFoto);
      expect(paginaTicket, findsOneWidget);
    });

    testWidgets('la marca y la acción se alcanzan con letra al 200 % a 320×568', (tester) async {
      await _montar(tester, escala: 2, tamano: const Size(320, 568));

      await traerAlAlcance(tester, _marca);
      expect(tester.takeException(), isNull);
      await tocar(tester, _sacarFoto);

      expect(paginaTicket, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

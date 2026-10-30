// 29A·03 · Tarjeta registrada (V2, con foto) de la vista 29 (HU-COB-007, #427): el acceso desde el
// cobro a la foto del ticket. Sin cámara (la librería espera a Cristian) sigue el aviso de 29A·02.
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/services/captura_de_foto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/cobro_arnes.dart';
import '../../helpers/ticket_tarjeta_arnes.dart';

final _tarjeta = find.byKey(const Key('cobro_medio_1'));
final _sacarFoto = find.byKey(const Key('cobro_sacar_foto_del_ticket'));
final _despues = find.byKey(const Key('cobro_listo'));

/// Monta el cobro con los dobles de la foto y registra un cobro con tarjeta de [monto].
Future<({ArnesCobro cobro, ArnesTicket ticket})> _cobrarConTarjeta(
  WidgetTester tester, {
  String monto = '300',
  bool conCamara = true,
  CapturadorDePrueba? capturador,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  final ticket = nuevoArnesTicket(capturador: capturador);
  final cobro = await montarCobro(
    tester,
    escala: escala,
    tamano: tamano,
    overrides: overridesDeTicket(ticket, conCamara: conCamara, conConexion: false),
  );
  await tocarCobro(tester, _tarjeta);
  await escribirMonto(tester, monto);
  await tocarCobro(tester, botonRegistrar);
  return (cobro: cobro, ticket: ticket);
}

void main() {
  group('29A·03 · Tarjeta registrada, con foto', () {
    testWidgets('con cámara pide la foto del ticket o «Después», sin el aviso de guardarlo', (
      tester,
    ) async {
      await _cobrarConTarjeta(tester, monto: '1200');

      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(find.text(r'Sumamos $ 1.200 a tu dinero depositado.'), findsOneWidget);
      expect(find.text('Sacar foto del ticket'), findsOneWidget);
      expect(find.text('Después'), findsOneWidget);
      expect(find.byKey(const Key('cobro_aviso_ticket')), findsNothing);
      // Venta pagada del todo: nada más que agendar.
      expect(find.text('Agendar la próxima cobranza'), findsNothing);
    });

    testWidgets('con saldo pendiente también ofrece agendar la próxima cobranza', (tester) async {
      await _cobrarConTarjeta(tester, monto: '300');

      expect(find.text('Sacar foto del ticket'), findsOneWidget);
      expect(find.text('Agendar la próxima cobranza'), findsOneWidget);
      expect(find.text('Después'), findsOneWidget);
    });

    testWidgets('sin cámara sigue el aviso de guardar el ticket y «Listo» (29A·02)', (tester) async {
      await _cobrarConTarjeta(tester, monto: '1200', conCamara: false);

      expect(find.byKey(const Key('cobro_aviso_ticket')), findsOneWidget);
      expect(find.text('Sacar foto del ticket'), findsNothing);
      expect(find.text('Listo'), findsOneWidget);
    });

    testWidgets('el efectivo no ofrece la foto del ticket', (tester) async {
      final ticket = nuevoArnesTicket();
      await montarCobro(tester, overrides: overridesDeTicket(ticket, conConexion: false));
      await escribirMonto(tester, '300');
      await tocarCobro(tester, botonRegistrar);

      expect(find.text('Sacar foto del ticket'), findsNothing);
    });

    testWidgets('«Después» cierra el cobro y vuelve a la casa, sin ticket', (tester) async {
      final a = await _cobrarConTarjeta(tester, monto: '1200');

      await tocarCobro(tester, _despues);

      expect(a.cobro.resultados, [true]);
      expect(a.ticket.repo.recibidos, isEmpty);
    });

    testWidgets('«Sacar foto del ticket» abre la cámara; «✕» vuelve al cobro registrado', (
      tester,
    ) async {
      final a = await _cobrarConTarjeta(tester, monto: '1200');

      await tocarCobro(tester, _sacarFoto);
      expect(find.text('Encuadrá el ticket entero dentro del marco'), findsOneWidget);
      expect(find.text('TICKET DE TARJETA'), findsOneWidget);

      await tocarTicket(tester, atrasTicket);

      expect(find.text('Cobro registrado'), findsOneWidget);
      expect(find.text('Sacar foto del ticket'), findsOneWidget);
      expect(a.cobro.resultados, isEmpty);
    });

    testWidgets('doble toque en «Sacar foto del ticket» abre una sola pantalla', (tester) async {
      await _cobrarConTarjeta(tester, monto: '1200');

      await tester.tap(_sacarFoto);
      await tester.tap(_sacarFoto, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(paginaTicket, findsOneWidget);
      // Una sola «✕» alcanza para volver: no se abrieron dos pantallas.
      await tocarTicket(tester, atrasTicket);
      expect(paginaTicket, findsNothing);
      expect(find.text('Cobro registrado'), findsOneWidget);
    });

    testWidgets('«Después» de la pantalla sin permiso cierra el cobro también', (tester) async {
      final a = await _cobrarConTarjeta(
        tester,
        monto: '1200',
        capturador: CapturadorDePrueba(camara: const [CapturaSinPermiso()]),
      );
      await tocarCobro(tester, _sacarFoto);
      await tocarTicket(tester, find.byKey(const Key('ticket_sacar_foto')));

      await tocarTicket(tester, find.byKey(const Key('ticket_despues')));

      expect(a.cobro.resultados, [true]);
      expect(find.text('Necesitamos la cámara'), findsNothing);
    });

    testWidgets('el flujo completo con «Listo» vuelve a la casa con el cobro hecho', (tester) async {
      final a = await _cobrarConTarjeta(tester, monto: '1200');
      await tocarCobro(tester, _sacarFoto);

      await tocarTicket(tester, find.byKey(const Key('ticket_sacar_foto')));
      await tocarTicket(tester, find.byKey(const Key('ticket_se_lee_bien')));
      await traerTicketAlAlcance(tester, campoAutorizacion);
      await tester.enterText(campoAutorizacion, '004512');
      await asentarAgendar(tester, 3);
      await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));

      final enviado = a.ticket.repo.recibidos.single;
      expect(enviado.cobroId, a.cobro.repo.recibidos.single.id);
      expect(enviado.ticket.montoCentavos, 120000);

      a.ticket.repo.cambiar(
        estado: EstadoDeSubida.subida,
        urlCloud: 'col-1/tk-1.jpg',
        quitarElError: true,
      );
      await asentarAgendar(tester);
      await tocarTicket(tester, find.byKey(const Key('ticket_listo')));

      expect(a.cobro.resultados, [true]);
    });

    testWidgets('textScaler 2.0 a 320×568: el cobro registrado entra sin desbordar', (tester) async {
      await _cobrarConTarjeta(
        tester,
        monto: '300',
        escala: 2,
        tamano: const Size(320, 568),
      );

      await traerAlAlcance(tester, _sacarFoto);
      expect(find.text('Sacar foto del ticket'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

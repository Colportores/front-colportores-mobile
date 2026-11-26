// El detalle de un ticket (vista 38B·02 rechazado y 38B·03 validado, HU-COB-009, #388) y «Cargar de
// nuevo»: el estado con lo que pasó, la foto (del teléfono o de la nube), los datos y los casos límite
// (foto vencida, sin red, sin enviar, doble toque, falla al registrar, volver atrás, texto al 200 %).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/presentation/textos_deposito.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart'
    show TextosDescartar;
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/services/visor_de_fotos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/deposito_arnes.dart';
import '../../helpers/historial_tickets_arnes.dart';
import '../../helpers/tickets_falsos.dart';

Finder _texto(String t) => find.text(t, findRichText: true);

/// Monta «Mis tickets» y abre el detalle de la fila [id].
Future<ArnesDeDeposito> _abrirDetalle(
  WidgetTester tester,
  String id, {
  HistorialControlable? repo,
  ArnesDeDeposito? arnes,
  VisorGuionado? visor,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  final a = arnes ?? ArnesDeDeposito();
  await montarHistorial(
    tester,
    repo ?? HistorialControlable(inicial: historialCon(filasDelCanvas())),
    arnes: a,
    visor: visor,
    tamano: tamano,
    escala: escala,
  );
  // Con letra grande y pantalla chica la fila puede estar bajo el pliegue de la lista.
  await tester.scrollUntilVisible(
    fila(id),
    100,
    scrollable: find
        .descendant(of: find.byKey(const Key('tickets_lista')), matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(fila(id));
  await tester.pump();
  // Arriba a la izquierda de la tarjeta: con un motivo larguísimo el centro queda fuera de la pantalla.
  await tester.tapAt(tester.getTopLeft(fila(id)) + const Offset(30, 30));
  await tester.pumpAndSettle();
  return a;
}

void main() {
  group('38B·02 · rechazado', () {
    testWidgets(
      'el motivo con las palabras del coordinador, la foto, los datos y «Cargar de nuevo»',
      (tester) async {
        final arnes = ArnesDeDeposito();
        arnes.tickets.fotosLocales['t-d2'] = fotoDePrueba(300);
        await _abrirDetalle(tester, 'd2', arnes: arnes);

        expect(_texto('TICKET DEL 20/10'), findsOneWidget);
        expect(_texto(r'$ 2.000'), findsOneWidget);
        expect(_texto('Banco · casa editora'), findsOneWidget);
        expect(
          _texto('Tu coordinador lo rechazó: «La foto no se lee». No se acreditó.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('ticket_aviso_rechazado')), findsOneWidget);
        expect(find.byKey(const Key('ticket_foto')), findsOneWidget);
        expect(_texto('Fecha'), findsOneWidget);
        expect(_texto('20/10'), findsOneWidget);
        expect(_texto('Autorización'), findsOneWidget);
        expect(_texto('003981'), findsOneWidget);
        expect(_texto('Tarjeta'), findsOneWidget);
        expect(_texto('No'), findsOneWidget);
        expect(_texto('Cargar de nuevo'), findsOneWidget);
      },
    );

    testWidgets('un rechazo sin motivo dice solo lo que pasó', (tester) async {
      final repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d2', estado: EstadoDelItem.rechazado)]),
      );
      await _abrirDetalle(tester, 'd2', repo: repo);

      expect(_texto('Tu coordinador lo rechazó. No se acreditó.'), findsOneWidget);
    });

    testWidgets('«Cargar de nuevo» abre el formulario con lo mismo cargado, menos la foto', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      await _abrirDetalle(tester, 'd2', arnes: arnes);

      await tester.tap(find.byKey(const Key('ticket_cargar_de_nuevo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);
      expect(find.text('2.000'), findsOneWidget, reason: 'el monto');
      expect(find.text('003981'), findsOneWidget, reason: 'el número de autorización');
      expect(
        find.byKey(const Key('deposito_foto_miniatura')),
        findsNothing,
        reason: 'la foto se saca otra vez',
      );
      expect(botonRegistrar(tester).onPressed, isNull, reason: 'sin foto no se registra');
    });

    testWidgets('con la foto nueva se registra otro depósito con el mismo monto, fecha y número', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      await _abrirDetalle(tester, 'd2', arnes: arnes);
      await tester.tap(find.byKey(const Key('ticket_cargar_de_nuevo')));
      await tester.pumpAndSettle();

      await sacarLaFoto(tester);
      await tocarRegistrar(tester);

      final deposito = arnes.depositos.guardados.single;
      expect(deposito.montoCentavos, 200000);
      expect(deposito.destino, DestinoDeDeposito.banco);
      expect(deposito.concepto, ConceptoDeDeposito.casaEditora);
      expect(deposito.fecha, DateTime.utc(2026, 10, 20, 15));
      expect(arnes.tickets.guardados.single.ticket.numeroAutorizacion, '003981');
      expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
      expect(find.byKey(const Key('deposito_ver_mis_tickets')), findsNothing);

      await tester.tap(find.byKey(const Key('deposito_listo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ticket_detalle')), findsNothing, reason: 'vuelve a la lista');
      expect(find.byKey(const Key('tickets_pagina')), findsOneWidget);
    });

    testWidgets('si falla al registrar, lo cargado sigue y el botón vuelve a responder', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito()
        ..depositos.fallarUnaVezCon = const FailureDepositoNoGuardado(causa: 'SqliteException');
      await _abrirDetalle(tester, 'd2', arnes: arnes);
      await tester.tap(find.byKey(const Key('ticket_cargar_de_nuevo')));
      await tester.pumpAndSettle();
      await sacarLaFoto(tester);

      await tocarRegistrar(tester);

      expect(find.byKey(const Key('deposito_error')), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNotNull);
      expect(find.text('2.000'), findsOneWidget);

      await tocarRegistrar(tester);
      expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
      expect(arnes.depositos.guardados.map((d) => d.id), ['d-1', 'd-1']);
    });

    testWidgets('un doble toque en «Cargar de nuevo» abre un solo formulario', (tester) async {
      await _abrirDetalle(tester, 'd2');

      await tester.tap(find.byKey(const Key('ticket_cargar_de_nuevo')));
      await tester.tap(find.byKey(const Key('ticket_cargar_de_nuevo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextosDescartar.descartar));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsNothing, reason: 'no había dos');
      expect(find.byKey(const Key('ticket_detalle')), findsOneWidget, reason: 'vuelve al detalle');
    });

    testWidgets('descartar el formulario deja el detalle como estaba y se puede volver a abrir', (
      tester,
    ) async {
      await _abrirDetalle(tester, 'd2');
      await tester.tap(find.byKey(const Key('ticket_cargar_de_nuevo')));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextosDescartar.descartar));
      await tester.pumpAndSettle();
      expect(_texto('Cargar de nuevo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ticket_cargar_de_nuevo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);
      expect(find.text('2.000'), findsOneWidget);
    });

    testWidgets('un rechazo de tarjeta de crédito lleva la tarjeta al ticket nuevo', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      final repo = HistorialControlable(
        inicial: historialCon([
          itemDePrueba(
            'd2',
            estado: EstadoDelItem.rechazado,
            motivo: 'No coincide con el monto',
            pesos: 1000,
            tarjeta: TipoDeTarjeta.credito,
          ),
        ]),
      );
      await _abrirDetalle(tester, 'd2', repo: repo, arnes: arnes);
      expect(_texto('Crédito'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ticket_cargar_de_nuevo')));
      await tester.pumpAndSettle();
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);

      expect(arnes.tickets.guardados.single.ticket.tarjetaTipo, TipoDeTarjeta.credito);
    });

    testWidgets('un retiro rechazado se carga de nuevo como retiro, sin foto', (tester) async {
      final arnes = ArnesDeDeposito();
      final repo = HistorialControlable(
        inicial: historialCon([
          itemDePrueba(
            'r1',
            lugar: LugarDelTicket.retiro,
            estado: EstadoDelItem.rechazado,
            motivo: 'No lo recibí',
            pesos: 1000,
            autorizacion: null,
            tarjeta: null,
          ),
        ]),
      );
      await _abrirDetalle(tester, 'r1', repo: repo, arnes: arnes);
      expect(find.byKey(const Key('ticket_foto')), findsNothing);

      await tester.tap(find.byKey(const Key('ticket_cargar_de_nuevo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_retiro_sin_foto')), findsOneWidget);
      await tocarRegistrar(tester);

      expect(arnes.depositos.guardados.single.destino, DestinoDeDeposito.retiroCoordinador);
      expect(arnes.tickets.guardados, isEmpty);
    });

    testWidgets('un ticket de un cobro con tarjeta rechazado ofrece «Cargar de nuevo» (#728)', (
      tester,
    ) async {
      final repo = HistorialControlable(
        inicial: historialCon([
          itemDePrueba(
            'c1',
            lugar: LugarDelTicket.cobroConTarjeta,
            concepto: null,
            estado: EstadoDelItem.rechazado,
            motivo: 'No se ve el número',
          ),
        ]),
      );
      await _abrirDetalle(tester, 'c1', repo: repo);

      expect(
        _texto('Tu coordinador lo rechazó: «No se ve el número». No se acreditó.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ticket_cargar_de_nuevo')), findsOneWidget);
    });
  });

  group('38B·03 · validado', () {
    testWidgets(
      'un retiro validado: cuándo se validó y a qué se acreditó, sin foto ni autorización',
      (tester) async {
        await _abrirDetalle(tester, 'd3');

        expect(_texto('TICKET DEL 15/10'), findsOneWidget);
        expect(_texto(r'$ 6.000'), findsOneWidget);
        expect(_texto('Retiro por el coordinador · alquiler'), findsOneWidget);
        expect(_texto('Validado el 16/10. Se acreditó al alquiler.'), findsOneWidget);
        expect(find.byKey(const Key('ticket_aviso_validado')), findsOneWidget);
        expect(find.byKey(const Key('ticket_foto')), findsNothing);
        expect(find.byKey(const Key('ticket_foto_cargando')), findsNothing);
        expect(_texto('Fecha'), findsOneWidget);
        expect(_texto('Autorización'), findsNothing);
        expect(_texto('Tarjeta'), findsNothing);
        expect(find.byKey(const Key('ticket_cargar_de_nuevo')), findsNothing);
      },
    );

    testWidgets('un depósito de casa editora validado dice a qué deuda se acreditó', (
      tester,
    ) async {
      await _abrirDetalle(tester, 'd4');

      expect(
        _texto('Validado el 09/10. Se acreditó a tu deuda con la casa editora.'),
        findsOneWidget,
      );
    });
  });

  group('devuelto (el coordinador devolvió un pago de alquiler validado)', () {
    testWidgets('dice que se devolvió y que no suma, sin «Cargar de nuevo»', (tester) async {
      final repo = HistorialControlable(
        inicial: historialCon([
          itemDePrueba('d1', estado: EstadoDelItem.devuelto, concepto: ConceptoDeDeposito.alquiler),
        ]),
      );
      await _abrirDetalle(tester, 'd1', repo: repo);

      expect(_texto('Tu coordinador te devolvió el pago. No suma a tu cuenta.'), findsOneWidget);
      expect(find.byKey(const Key('ticket_aviso_devuelto')), findsOneWidget);
      expect(_texto('Se acreditó al alquiler.'), findsNothing);
      expect(find.byKey(const Key('ticket_cargar_de_nuevo')), findsNothing);
    });

    testWidgets('la fila de la lista dice «Devuelto»', (tester) async {
      await montarHistorial(
        tester,
        HistorialControlable(
          inicial: historialCon([itemDePrueba('d1', estado: EstadoDelItem.devuelto)]),
        ),
        arnes: ArnesDeDeposito(),
      );

      expect(_texto('Devuelto'), findsOneWidget);
    });
  });

  group('por validar y en cola', () {
    testWidgets('por validar con ticket dice qué falta; un retiro, que falta que lo confirme', (
      tester,
    ) async {
      final repo = HistorialControlable(
        inicial: historialCon([
          itemDePrueba('d1'),
          itemDePrueba('r1', lugar: LugarDelTicket.retiro, autorizacion: null, tarjeta: null),
        ]),
      );
      await _abrirDetalle(tester, 'd1', repo: repo);
      expect(
        _texto('Queda por validar: se acredita cuando tu coordinador valide el ticket.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ticket_cargar_de_nuevo')), findsNothing);

      await volverAtras(tester);
      await tester.tap(fila('r1'));
      await tester.pumpAndSettle();
      expect(
        _texto('Queda por validar: se acredita cuando tu coordinador confirme el retiro.'),
        findsOneWidget,
      );
    });

    testWidgets('en cola dice que todavía no llegó al servidor', (tester) async {
      final repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d1', estado: EstadoDelItem.enCola)]),
      );
      await _abrirDetalle(tester, 'd1', repo: repo);

      expect(
        _texto('Todavía no llegó al servidor. Se envía cuando vuelva la conexión.'),
        findsOneWidget,
      );
    });

    testWidgets('el estado se actualiza solo cuando baja la validación', (tester) async {
      final repo = HistorialControlable(inicial: historialCon([itemDePrueba('d1')]));
      await _abrirDetalle(tester, 'd1', repo: repo);
      expect(find.byKey(const Key('ticket_aviso_porValidar')), findsOneWidget);

      repo.emitir(
        historialCon([
          itemDePrueba(
            'd1',
            estado: EstadoDelItem.validado,
            validadoEn: DateTime.utc(2026, 11, 11, 15),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ticket_aviso_porValidar')), findsNothing);
      expect(
        _texto('Validado el 11/11. Se acreditó a tu deuda con la casa editora.'),
        findsOneWidget,
      );
    });

    testWidgets('si la fila ya no está en el historial, se sigue mostrando la que se abrió', (
      tester,
    ) async {
      final repo = HistorialControlable(inicial: historialCon([itemDePrueba('d1')]));
      await _abrirDetalle(tester, 'd1', repo: repo);

      repo.emitir(historialCon(const []));
      await tester.pumpAndSettle();

      expect(_texto(r'$ 4.800'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('la foto', () {
    testWidgets('la copia del teléfono se ve y no se pide a la nube', (tester) async {
      final arnes = ArnesDeDeposito();
      arnes.tickets.fotosLocales['t-d1'] = fotoDePrueba(300);
      final visor = VisorGuionado();
      await _abrirDetalle(tester, 'd1', arnes: arnes, visor: visor);

      expect(find.byKey(const Key('ticket_foto')), findsOneWidget);
      expect(visor.pedidos, isEmpty);
    });

    testWidgets(
      'sin copia y ya subida, se pide a la nube (foto vencida: lo dice y los datos siguen)',
      (tester) async {
        final visor = VisorGuionado([const FotoVencida()]);
        final repo = HistorialControlable(
          inicial: historialCon([itemDePrueba('d1', fotoSubida: true, hayCopiaLocal: false)]),
        );
        await _abrirDetalle(tester, 'd1', repo: repo, visor: visor);

        expect(visor.pedidos, ['t-d1']);
        expect(find.byKey(const Key('ticket_foto_vencida')), findsOneWidget);
        expect(
          _texto(
            'La foto ya no está disponible: se guarda 4 meses. Los datos del ticket siguen acá.',
          ),
          findsOneWidget,
        );
        expect(_texto('004512'), findsOneWidget, reason: 'los datos siguen');
        expect(
          find.byKey(const Key('ticket_foto_reintentar')),
          findsNothing,
          reason: 'no hay qué reintentar',
        );
      },
    );

    testWidgets('sin red lo dice y «Reintentar» la vuelve a pedir', (tester) async {
      final visor = VisorGuionado([const FotoNoDisponible(sinRed: true), const SinFotoParaVer()]);
      final repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d1', fotoSubida: true, hayCopiaLocal: false)]),
      );
      await _abrirDetalle(tester, 'd1', repo: repo, visor: visor);

      expect(_texto('Sin conexión. La foto se ve cuando vuelva la red.'), findsOneWidget);
      expect(visor.pedidos, hasLength(1));

      await tester.tap(find.byKey(const Key('ticket_foto_reintentar')));
      await tester.pumpAndSettle();

      expect(visor.pedidos, hasLength(2));
      expect(find.byKey(const Key('ticket_foto_error')), findsNothing);
      expect(find.byKey(const Key('ticket_foto_sin_enviar')), findsOneWidget);
    });

    testWidgets('una falla del servidor es «No pudimos traer la foto» con «Reintentar»', (
      tester,
    ) async {
      final visor = VisorGuionado([const FotoNoDisponible()]);
      final repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d1', fotoSubida: true, hayCopiaLocal: false)]),
      );
      await _abrirDetalle(tester, 'd1', repo: repo, visor: visor);

      expect(_texto('No pudimos traer la foto.'), findsOneWidget);
      expect(find.byKey(const Key('ticket_foto_reintentar')), findsOneWidget);
    });

    testWidgets('abrir el detalle pide la foto una sola vez', (tester) async {
      final visor = VisorGuionado([const FotoVencida()]);
      final repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d1', fotoSubida: true, hayCopiaLocal: false)]),
      );
      await montarHistorial(tester, repo, visor: visor);

      await tester.tap(fila('d1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(visor.pedidos, hasLength(1));
    });

    testWidgets('sin copia y sin subir todavía: dice que se envía cuando vuelva la conexión', (
      tester,
    ) async {
      final repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d1', hayCopiaLocal: false)]),
      );
      final visor = VisorGuionado();
      await _abrirDetalle(tester, 'd1', repo: repo, visor: visor);

      expect(
        _texto('La foto todavía no se envió. Se envía cuando vuelva la conexión.'),
        findsOneWidget,
      );
      expect(visor.pedidos, isEmpty, reason: 'no está en la nube: no hay qué pedir');
    });

    testWidgets('una foto que el servidor rechazó para siempre dice que se avise al coordinador', (
      tester,
    ) async {
      final repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d1', hayCopiaLocal: false, fotoRechazada: true)]),
      );
      await _abrirDetalle(tester, 'd1', repo: repo);

      expect(
        _texto('La foto no se pudo enviar y ya no se puede reintentar. Avisale a tu coordinador.'),
        findsOneWidget,
      );
    });
  });

  group('datos límite', () {
    testWidgets(
      'el rechazo con un motivo larguísimo al 200 % en 320×568 no desborda y llega a «Cargar de nuevo»',
      (tester) async {
        final largo = List.filled(
          15,
          'La foto está movida y no se alcanza a leer el número',
        ).join(' ');
        final repo = HistorialControlable(
          inicial: historialCon([
            itemDePrueba(
              'd2',
              estado: EstadoDelItem.rechazado,
              motivo: largo,
              pesos: 21000000,
              autorizacion: List.filled(40, '9').join(),
            ),
          ]),
        );
        await _abrirDetalle(tester, 'd2', repo: repo, tamano: const Size(320, 568), escala: 2);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('ticket_cargar_de_nuevo')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('ticket_foto_sin_enviar')),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('ticket_detalle_lista')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}

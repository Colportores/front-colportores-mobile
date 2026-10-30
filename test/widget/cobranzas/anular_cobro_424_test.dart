// «Detalle del cobro» y «Anular cobro» (vista 30 B, HU-COB-006, #424): un grupo por artboard (30B-01 a
// 30B-08) y los casos límite de cada flujo: doble toque, falla a mitad de la acción, dos acciones
// seguidas, volver atrás y reentrar, y datos límite (textos largos, textScaler 2.0).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/usecases/anular_cobro_use_case.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/anular_cobro_arnes.dart';

void main() {
  group('30B-01 · Detalle del cobro', () {
    testWidgets('dado el canvas, cuando se abre, entonces dibuja el cobro y hasta cuándo anular', (
      tester,
    ) async {
      await montarDetalleDelCobro(tester);

      expect(paginaDetalle, findsOneWidget);
      expect(find.text('COBRO'), findsOneWidget);
      expect(find.text(r'$ 600 en efectivo'), findsOneWidget);
      expect(find.text('María Fernández · venta 0042'), findsOneWidget);
      expect(textoDe('detalle_cobro_fecha'), 'Hoy 14:10');
      expect(textoDe('detalle_cobro_medio'), 'Efectivo');
      expect(textoDe('detalle_cobro_estado'), 'Registrado');
      expect(find.text('Anular cobro'), findsOneWidget);
      // 72 h después del cobro (viernes 23/10 14:10 en Montevideo).
      expect(textoDe('detalle_cobro_plazo'), 'Podés anularlo hasta el lunes 26/10 a las 14:10.');
      expect(find.byKey(const Key('detalle_cobro_aviso_info')), findsNothing);
      expect(find.byKey(const Key('detalle_cobro_ticket_validado')), findsNothing);
    });

    testWidgets('el título dice el medio: tarjeta y transferencia', (tester) async {
      await montarDetalleDelCobro(
        tester,
        repo: AnulacionesEnMemoria(cobros: [detalleDeEjemplo(medio: MedioCobranza.tarjeta)]),
      );
      expect(find.text(r'$ 600 con tarjeta'), findsOneWidget);
      expect(textoDe('detalle_cobro_medio'), 'Tarjeta');
    });

    testWidgets('un cobro de ayer dice «Ayer» y uno más viejo, el día', (tester) async {
      await montarDetalleDelCobro(
        tester,
        repo: AnulacionesEnMemoria(
          cobros: [detalleDeEjemplo(fecha: DateTime.utc(2026, 10, 22, 12, 30))],
        ),
      );
      expect(textoDe('detalle_cobro_fecha'), 'Ayer 09:30');
    });

    testWidgets('sin el nombre del cliente la línea de abajo solo dice la venta', (tester) async {
      await montarDetalleDelCobro(
        tester,
        repo: AnulacionesEnMemoria(cobros: [detalleDeEjemplo(cliente: null)]),
      );
      expect(find.text('venta 0042'), findsOneWidget);
    });

    testWidgets('«✕»-«‹» vuelve con false y no anula nada', (tester) async {
      final a = await montarDetalleDelCobro(tester);

      await tocar(tester, find.byKey(const Key('venta_atras')));

      expect(paginaDetalle, findsNothing);
      expect(a.resultados, [false]);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('cargando: el esqueleto dice qué carga y, al llegar, el detalle', (tester) async {
      final repo = AnulacionesEnMemoria()..compuertaDeLectura = Completer<void>();
      await montarDetalleDelCobro(tester, repo: repo);

      expect(find.byKey(const Key('cobro_cargando')), findsOneWidget);
      expect(find.bySemanticsLabel('Cargando el cobro'), findsOneWidget);

      repo.compuertaDeLectura!.complete();
      await asentarAgendar(tester);

      expect(find.byKey(const Key('cobro_cargando')), findsNothing);
      expect(botonAnularDelDetalle, findsOneWidget);
    });

    testWidgets('el cobro ya no está: lo dice y «Volver» cierra', (tester) async {
      final a = await montarDetalleDelCobro(tester, cobranzaId: 'nada');

      expect(find.byKey(const Key('detalle_cobro_ausente')), findsOneWidget);
      expect(botonAnularDelDetalle, findsNothing);
      await tocar(tester, find.text('Volver'));
      expect(a.resultados, [false]);
    });

    testWidgets('error al leer: «Reintentar» vuelve a leer y muestra el cobro', (tester) async {
      final repo = AnulacionesEnMemoria()
        ..fallaDeLectura = const FailureCobroNoAnulado()
        ..fallaDeLecturaUnaVez = true;
      await montarDetalleDelCobro(tester, repo: repo);

      expect(find.byKey(const Key('detalle_cobro_error_lectura')), findsOneWidget);
      await tocar(tester, find.byKey(const Key('venta_aviso_accion')));

      expect(find.byKey(const Key('detalle_cobro_error_lectura')), findsNothing);
      expect(botonAnularDelDetalle, findsOneWidget);
      expect(repo.lecturas, 2);
    });
  });

  group('30B-02 · Motivo obligatorio', () {
    testWidgets('dado el detalle, cuando toca «Anular cobro», entonces pide el motivo', (
      tester,
    ) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(tester);

      expect(paginaAnular, findsOneWidget);
      expect(find.text('ANULAR COBRO'), findsOneWidget);
      expect(find.text('¿Por qué lo anulás?'), findsOneWidget);
      expect(find.text(r'$ 600 · hoy 14:10 · María Fernández'), findsOneWidget);
      expect(find.text('MOTIVO'), findsOneWidget);
      for (final t in ['Monto equivocado', 'Cliente equivocado', 'Lo registré dos veces', 'Otro']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text('Elegí el motivo para seguir.'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
      expect(find.byKey(const Key('anular_cobro_otro')), findsNothing);
    });

    testWidgets('sin motivo, tocar el botón apagado no hace nada', (tester) async {
      final a = await montarDetalleDelCobro(tester);
      await irAAnular(tester);

      await tester.tap(botonPrincipal, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(siAnular, findsNothing);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('al elegir un motivo el botón se enciende y la nota se va', (tester) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);

      expect(elBoton(tester).onPressed, isNotNull);
      expect(find.text('Elegí el motivo para seguir.'), findsNothing);
    });

    testWidgets('la ✕ cierra sin anular; el detalle sigue igual', (tester) async {
      final a = await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);

      await tocar(tester, find.byKey(const Key('venta_atras')));

      expect(paginaAnular, findsNothing);
      expect(botonAnularDelDetalle, findsOneWidget);
      expect(a.repo.recibidos, isEmpty);
    });
  });

  group('30B-03 · Motivo «Otro»', () {
    testWidgets('pide «Contanos qué pasó» y, hasta escribir, no deja seguir', (tester) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.otro);

      expect(find.text('CONTANOS QUÉ PASÓ'), findsOneWidget);
      expect(find.text('Contanos qué pasó para seguir.'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);

      await tester.enterText(campoOtro, '   \n  ');
      await asentarAgendar(tester, 3);
      expect(elBoton(tester).onPressed, isNull, reason: 'solo espacios no cuentan');

      await tester.enterText(campoOtro, 'El cliente pagó con transferencia');
      await asentarAgendar(tester, 3);
      expect(elBoton(tester).onPressed, isNotNull);
      expect(find.text('Contanos qué pasó para seguir.'), findsNothing);
    });

    testWidgets('cambiar a otro motivo saca el campo y vuelve a dejar seguir', (tester) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.otro);
      expect(elBoton(tester).onPressed, isNull);

      await tocar(tester, motivo(MotivoDeAnulacion.clienteEquivocado));

      expect(find.byKey(const Key('anular_cobro_otro')), findsNothing);
      expect(elBoton(tester).onPressed, isNotNull);
    });

    testWidgets('el texto tiene tope de 200 caracteres', (tester) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: 'ñ' * 250);

      expect(tester.widget<TextField>(campoOtro).controller!.text.length, 200);
      expect(AnularCobroUseCase.maximoJustificacion, 200);
    });

    testWidgets('atrás con lo escrito pregunta; «Descartar» sale y «Seguir» se queda', (
      tester,
    ) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: 'algo');

      await tocar(tester, find.byKey(const Key('venta_atras')));
      expect(find.text('Descartar'), findsOneWidget);
      await tocar(tester, find.text('Seguir escribiendo'));
      expect(paginaAnular, findsOneWidget);
      expect(tester.widget<TextField>(campoOtro).controller!.text, 'algo');

      await tocar(tester, find.byKey(const Key('venta_atras')));
      await tocar(tester, find.text('Descartar'));
      expect(paginaAnular, findsNothing);
    });
  });

  group('30B-04 · Segunda confirmación', () {
    testWidgets('dice qué pasa con el saldo y el dinero en mano, y que no se deshace', (
      tester,
    ) async {
      final a = await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);

      await tocar(tester, botonPrincipal);

      expect(textoDe('anular_cobro_confirmar_titulo'), r'¿Anular el cobro de $ 600?');
      expect(
        textoDe('anular_cobro_confirmar_texto'),
        r'El saldo de la venta vuelve a $ 1.200 y se resta $ 600 de tu dinero en mano. '
        'No se puede deshacer.',
      );
      expect(find.text('Sí, anular'), findsOneWidget);
      expect(find.text('No, volver'), findsOneWidget);
      expect(a.repo.recibidos, isEmpty, reason: 'hasta el «Sí» no se anula nada');
    });

    testWidgets('con tarjeta, lo que se resta es del dinero depositado', (tester) async {
      await montarDetalleDelCobro(
        tester,
        repo: AnulacionesEnMemoria(cobros: [detalleDeEjemplo(medio: MedioCobranza.tarjeta)]),
      );
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);

      expect(textoDe('anular_cobro_confirmar_texto'), contains('de tu dinero depositado'));
    });

    testWidgets('«No, volver» cierra la hoja, conserva lo elegido y no anula', (tester) async {
      final a = await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.clienteEquivocado);
      await tocar(tester, botonPrincipal);

      await tocar(tester, noVolver);

      expect(siAnular, findsNothing);
      expect(paginaAnular, findsOneWidget);
      expect(elBoton(tester).onPressed, isNotNull);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('doble toque en el botón no abre dos hojas', (tester) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);

      await tester.tap(botonPrincipal);
      await tester.tap(botonPrincipal, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(siAnular, findsOneWidget);
    });
  });

  group('30B-05 · Anulado', () {
    testWidgets('«Sí, anular» vuelve al detalle: avisa, marca el estado y muestra el saldo', (
      tester,
    ) async {
      final a = await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);

      await tocar(tester, siAnular);

      expect(paginaAnular, findsNothing);
      expect(find.text(r'Cobro anulado. El saldo volvió a $ 1.200.'), findsOneWidget);
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
      expect(textoDe('cobro_pagado'), r'$ 3.300');
      expect(textoDe('cobro_saldo'), r'$ 1.200');
      expect(botonAnularDelDetalle, findsNothing);
      expect(find.byKey(const Key('detalle_cobro_plazo')), findsNothing);
      final pedido = a.repo.recibidos.single;
      expect(
        [pedido.id, pedido.motivo, pedido.justificacion],
        ['c-1', MotivoDeAnulacion.montoEquivocado, null],
      );
      expect(pedido.ahora, ahoraDeLaAnulacion);
    });

    testWidgets('con «Otro» lo escrito viaja sin espacios de más', (tester) async {
      final a = await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: '  Pagó  con\ntransferencia  ');
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);

      expect(a.repo.recibidos.single.justificacion, 'Pagó con transferencia');
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Otro');
    });

    testWidgets(
      'al salir, la pantalla devuelve true; al volver a abrirlo sigue anulado y sin aviso',
      (tester) async {
        final a = await montarDetalleDelCobro(tester);
        await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
        await tocar(tester, botonPrincipal);
        await tocar(tester, siAnular);

        await tocar(tester, find.byKey(const Key('venta_atras')));
        expect(a.resultados, [true]);

        await abrirDetalle(tester);
        expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
        expect(find.textContaining('Cobro anulado.'), findsNothing);
        expect(botonAnularDelDetalle, findsNothing);
      },
    );

    testWidgets('doble toque en «Sí, anular» anula una sola vez', (tester) async {
      final a = await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);

      await tester.tap(siAnular);
      await tester.tap(siAnular, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(a.repo.recibidos, hasLength(1));
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
    });

    testWidgets('anulando: el botón queda ocupado, no deja salir y no admite otro toque', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria()..compuerta = Completer<void>();
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);

      expect(find.text('Anulando…'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
      expect(find.byKey(const Key('venta_atras')), findsNothing, reason: 'no deja salir');
      await tester.tap(botonPrincipal, warnIfMissed: false);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(paginaAnular, findsOneWidget);
      expect(repo.recibidos, hasLength(1));

      repo.compuerta!.complete();
      await asentarAgendar(tester);
      expect(paginaAnular, findsNothing);
    });

    testWidgets('con el resultado «ya estaba anulado» (otro toque) se muestra anulado igual', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria(
        cobros: [
          detalleDeEjemplo(
            cobrado: 330000,
            anuladoAt: ahoraDeLaAnulacion,
            motivo: MotivoDeAnulacion.registreDosVeces,
          ),
        ],
      );
      await montarDetalleDelCobro(tester, repo: repo);

      expect(textoDe('detalle_cobro_estado'), 'Anulado · Lo registré dos veces');
      expect(botonAnularDelDetalle, findsNothing);
      expect(find.textContaining('Cobro anulado.'), findsNothing);
    });
  });

  group('30B-06 · Pasaron las 72 h', () {
    testWidgets('lo dice, sin botón ni plazo, para todos', (tester) async {
      await montarDetalleDelCobro(tester, ahora: DateTime.utc(2026, 10, 26, 17, 10, 1));

      expect(
        find.text('Pasaron más de 72 h desde el cobro: ya no se puede anular.'),
        findsOneWidget,
      );
      expect(botonAnularDelDetalle, findsNothing);
      expect(find.byKey(const Key('detalle_cobro_plazo')), findsNothing);
      expect(textoDe('detalle_cobro_estado'), 'Registrado');
    });

    testWidgets('a las 72 h justas todavía se puede', (tester) async {
      await montarDetalleDelCobro(tester, ahora: DateTime.utc(2026, 10, 26, 17, 10));

      expect(botonAnularDelDetalle, findsOneWidget);
    });

    testWidgets('si el plazo se cumple con la pantalla abierta, el toque la redibuja como 30B-06', (
      tester,
    ) async {
      final a = await montarDetalleDelCobro(tester, ahora: DateTime.utc(2026, 10, 26, 17));
      a.ahora = DateTime.utc(2026, 10, 26, 17, 30);

      await tocar(tester, botonAnularDelDetalle);

      expect(paginaAnular, findsNothing);
      expect(botonAnularDelDetalle, findsNothing);
      expect(find.byKey(const Key('detalle_cobro_aviso_info')), findsOneWidget);
      expect(a.repo.recibidos, isEmpty);
    });

    testWidgets('si el servidor-teléfono lo rechaza por plazo, vuelve al detalle y lo dice', (
      tester,
    ) async {
      final a = await montarDetalleDelCobro(tester, ahora: DateTime.utc(2026, 10, 26, 17));
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      a.ahora = DateTime.utc(2026, 10, 26, 17, 30);

      await tocar(tester, siAnular);

      expect(paginaAnular, findsNothing);
      expect(find.byKey(const Key('detalle_cobro_aviso_info')), findsOneWidget);
      expect(botonAnularDelDetalle, findsNothing);
      expect(textoDe('detalle_cobro_estado'), 'Registrado');
    });
  });

  group('30B-07 · Ticket validado', () {
    testWidgets('el aviso y la salida son los de la decisión del 23/10', (tester) async {
      await montarDetalleDelCobro(
        tester,
        repo: AnulacionesEnMemoria(cobros: [detalleDeEjemplo(medio: MedioCobranza.tarjeta)]),
        ticketValidado: true,
      );

      expect(find.byKey(const Key('detalle_cobro_ticket_validado')), findsOneWidget);
      expect(
        find.textContaining('El ticket de este cobro ya lo validó tu coordinador.'),
        findsOneWidget,
      );
      expect(find.textContaining('Pedíselo a tu coordinador'), findsOneWidget);
      expect(botonAnularDelDetalle, findsNothing);
      expect(find.byKey(const Key('detalle_cobro_plazo')), findsNothing);
    });

    testWidgets('un cobro ya anulado no muestra el aviso del ticket', (tester) async {
      await montarDetalleDelCobro(
        tester,
        repo: AnulacionesEnMemoria(
          cobros: [
            detalleDeEjemplo(
              cobrado: 330000,
              anuladoAt: ahoraDeLaAnulacion,
              motivo: MotivoDeAnulacion.otro,
            ),
          ],
        ),
        ticketValidado: true,
      );

      expect(find.byKey(const Key('detalle_cobro_ticket_validado')), findsNothing);
    });
  });

  group('30B-08 · Error al anular', () {
    Future<ArnesAnular> hastaElError(WidgetTester tester, {Object? lanza}) async {
      final repo = AnulacionesEnMemoria();
      if (lanza == null) {
        repo.fallas.add(const FailureCobroNoAnulado());
      } else {
        repo.lanzar = lanza;
      }
      final a = await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.clienteEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
      return a;
    }

    testWidgets(
      'un fallo: el aviso del canvas, el botón vuelve a habilitarse y nada queda trabado',
      (tester) async {
        final a = await hastaElError(tester);

        expect(paginaAnular, findsOneWidget);
        expect(
          find.text('No pudimos anular el cobro. Sigue registrado como estaba.'),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.text('Anulando…'), findsNothing);
        expect(elBoton(tester).onPressed, isNotNull);
        expect(
          tester.widget<IconButton>(find.byKey(const Key('venta_atras'))).onPressed,
          isNotNull,
        );
        expect(a.repo.detalles['c-1']!.cobranza.estaAnulado, isFalse);
      },
    );

    testWidgets('una excepción se trata igual que una falla', (tester) async {
      await hastaElError(tester, lanza: StateError('boom'));

      expect(find.byKey(const Key('anular_cobro_error')), findsOneWidget);
      expect(elBoton(tester).onPressed, isNotNull);
    });

    testWidgets('«Reintentar» anula sin volver a preguntar y vuelve al detalle anulado', (
      tester,
    ) async {
      final a = await hastaElError(tester);

      await tocar(tester, botonPrincipal);

      expect(siAnular, findsNothing, reason: 'ya confirmó: no se le pregunta de nuevo');
      expect(paginaAnular, findsNothing);
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Cliente equivocado');
      expect(a.repo.recibidos, hasLength(2));
    });

    testWidgets('doble toque en «Reintentar» no anula dos veces', (tester) async {
      final a = await hastaElError(tester);

      await tester.tap(botonPrincipal);
      await tester.tap(botonPrincipal, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(a.repo.recibidos, hasLength(2));
    });

    testWidgets('cambiar el motivo después del error vuelve a pedir la confirmación', (
      tester,
    ) async {
      await hastaElError(tester);

      await tocar(tester, motivo(MotivoDeAnulacion.montoEquivocado));

      expect(find.byKey(const Key('anular_cobro_error')), findsNothing);
      expect(find.text('Anular cobro'), findsWidgets);
      await tocar(tester, botonPrincipal);
      expect(siAnular, findsOneWidget);
    });
  });

  group('Volver atrás y reentrar', () {
    testWidgets('cancelar en cualquier paso y reabrir deja el cobro vigente y sin lo elegido', (
      tester,
    ) async {
      final a = await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.clienteEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, noVolver);
      await tocar(tester, find.byKey(const Key('venta_atras')));
      await tocar(tester, find.byKey(const Key('venta_atras')));
      expect(a.resultados, [false]);

      await abrirDetalle(tester);
      await tocar(tester, botonAnularDelDetalle);

      expect(find.text('Elegí el motivo para seguir.'), findsOneWidget);
      expect(a.repo.recibidos, isEmpty);
      expect(a.repo.detalles['c-1']!.cobranza.estaAnulado, isFalse);
    });
  });

  group('Datos límite · textScaler 2.0', () {
    testWidgets('el detalle, el motivo, «Otro», la confirmación y el error se pueden recorrer', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria(
        cobros: [
          detalleDeEjemplo(cliente: 'María de los Ángeles Fernández de la Torre Etcheverry'),
        ],
      )..fallas.add(const FailureCobroNoAnulado());
      await montarDetalleDelCobro(tester, repo: repo, escala: 2, tamano: const Size(360, 640));

      expect(botonAnularDelDetalle, findsOneWidget);
      await tocar(tester, botonAnularDelDetalle);
      await tocar(tester, motivo(MotivoDeAnulacion.otro));
      await traerAlAlcance(tester, campoOtro);
      await tester.enterText(campoOtro, 'Un texto largo ' * 12);
      await asentarAgendar(tester, 3);
      await tocar(tester, botonPrincipal);
      expect(siAnular, findsOneWidget);
      await tocar(tester, siAnular);
      await traerAlAlcance(tester, find.byKey(const Key('anular_cobro_error')));
      expect(find.byKey(const Key('anular_cobro_error')), findsOneWidget);
      await tocar(tester, botonPrincipal);

      await traerAlAlcance(tester, find.byKey(const Key('detalle_cobro_estado')));
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Otro');
      expect(tester.takeException(), isNull);
    });

    testWidgets('el monto grande y el detalle anulado entran en la pantalla chica', (tester) async {
      await montarDetalleDelCobro(
        tester,
        repo: AnulacionesEnMemoria(
          cobros: [
            detalleDeEjemplo(
              monto: 123456789,
              cobrado: 123456789,
              anuladoAt: ahoraDeLaAnulacion,
              motivo: MotivoDeAnulacion.registreDosVeces,
            ),
          ],
        ),
        escala: 2,
        tamano: const Size(320, 568),
      );

      await traerAlAlcance(tester, find.byKey(const Key('detalle_cobro_estado')));
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Lo registré dos veces');
      expect(tester.takeException(), isNull);
    });
  });
}

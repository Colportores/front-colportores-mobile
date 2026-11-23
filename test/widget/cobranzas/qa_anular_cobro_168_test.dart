// QA de «Detalle del cobro» y «Anular cobro» (vista 30 B, HU-COB-006, #168 / #422 / #424): los
// escenarios de la HU con su texto, los literales de cada artboard (30B-01 a 30B-08), los cinco estados,
// la validación de «Otro», los casos límite de cada flujo y la privacidad. Los hallazgos van con `skip`
// y se corren con `--dart-define=QA_HALLAZGOS=true`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/detalle_del_cobro.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/usecases/anular_cobro_use_case.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/anular_cobro_arnes.dart';

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// El cobro del canvas hecho el viernes 23/10 a las 14:10 (17:10 UTC).
final _fechaDelCobro = DateTime.utc(2026, 10, 23, 17, 10);

Finder _sinTocar(String t) => find.textContaining(t);

void main() {
  // ---------------------------------------------------------------------------------------------
  group('Criterios de aceptación de HU-COB-006', () {
    testWidgets(
      'Anular cobro dentro de ventana: dado un cobro de hace 1 h, cuando anulo con motivo, '
      'entonces queda ANULADO y el saldo vuelve a su valor previo',
      (tester) async {
        final repo = AnulacionesEnMemoria();
        final a = await montarDetalleDelCobro(
          tester,
          repo: repo,
          ahora: _fechaDelCobro.add(const Duration(hours: 1)),
        );
        await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
        await tocar(tester, botonPrincipal);
        await tocar(tester, siAnular);

        expect(repo.detalles['c-1']!.cobranza.estaAnulado, isTrue);
        expect(repo.detalles['c-1']!.cobranza.motivoAnulacion, MotivoDeAnulacion.montoEquivocado);
        // El saldo previo del canvas: $ 1.200 (antes del cobro de $ 600).
        expect(find.text(r'Cobro anulado. El saldo volvió a $ 1.200.'), findsOneWidget);
        expect(textoDe('cobro_saldo'), r'$ 1.200');
        expect(a.repo.recibidos.single.motivo, MotivoDeAnulacion.montoEquivocado);
      },
    );

    testWidgets(
      'Edge, cobro fijo pasado el plazo: dado que pasaron más de 72 h, cuando Ana intenta '
      'anularlo, entonces no puede',
      (tester) async {
        final repo = AnulacionesEnMemoria();
        await montarDetalleDelCobro(
          tester,
          repo: repo,
          ahora: _fechaDelCobro.add(const Duration(hours: 72, minutes: 1)),
        );

        expect(botonAnularDelDetalle, findsNothing);
        expect(find.text('Anular cobro'), findsNothing);
        expect(
          find.text('Pasaron más de 72 h desde el cobro: ya no se puede anular.'),
          findsOneWidget,
        );
        expect(repo.recibidos, isEmpty);
        expect(textoDe('detalle_cobro_estado'), 'Registrado');
      },
    );

    testWidgets(
      'Anulación sin señal que sube tarde: dado un cobro anulado a las 70 h, vale la hora en '
      'que anuló (la del teléfono) y el cobro queda anulado',
      (tester) async {
        final hora = _fechaDelCobro.add(const Duration(hours: 70));
        final repo = AnulacionesEnMemoria();
        await montarDetalleDelCobro(tester, repo: repo, ahora: hora);
        await irAAnular(tester, m: MotivoDeAnulacion.registreDosVeces);
        await tocar(tester, botonPrincipal);
        await tocar(tester, siAnular);

        expect(repo.recibidos.single.ahora, hora);
        expect(repo.detalles['c-1']!.cobranza.anuladoAt, hora);
        expect(textoDe('detalle_cobro_estado'), 'Anulado · Lo registré dos veces');
      },
    );

    testWidgets('a las 72 h en punto todavía se puede y un minuto después ya no', (tester) async {
      final repo = AnulacionesEnMemoria();
      final a = await montarDetalleDelCobro(
        tester,
        repo: repo,
        ahora: _fechaDelCobro.add(const Duration(hours: 72)),
      );
      expect(botonAnularDelDetalle, findsOneWidget);
      a.ahora = _fechaDelCobro.add(const Duration(hours: 72, minutes: 1));
      await tocar(tester, botonAnularDelDetalle);
      expect(paginaAnular, findsNothing, reason: 'no abre «Anular» pasado el plazo');
      expect(find.textContaining('Pasaron más de 72 h'), findsOneWidget);
      expect(repo.recibidos, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('Literales del canvas, artboard por artboard', () {
    testWidgets('30B-01 · Detalle del cobro', (tester) async {
      await montarDetalleDelCobro(tester);
      for (final t in [
        'COBRO',
        r'$ 600 en efectivo',
        'María Fernández · venta 0042',
        'Fecha',
        'Medio',
        'Estado',
        'Anular cobro',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(textoDe('detalle_cobro_fecha'), 'Hoy 14:10');
      expect(textoDe('detalle_cobro_medio'), 'Efectivo');
      expect(textoDe('detalle_cobro_estado'), 'Registrado');
      expect(
        textoDe('detalle_cobro_plazo'),
        startsWith('Podés anularlo hasta el '),
        reason: 'el canvas: «Podés anularlo hasta el … a las 14:10.»',
      );
      expect(textoDe('detalle_cobro_plazo'), endsWith(' a las 14:10.'));
    });

    testWidgets('30B-02 · Motivo obligatorio', (tester) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(tester);
      for (final t in [
        'ANULAR COBRO',
        '¿Por qué lo anulás?',
        r'$ 600 · hoy 14:10 · María Fernández',
        'MOTIVO',
        'Monto equivocado',
        'Cliente equivocado',
        'Lo registré dos veces',
        'Otro',
        'Elegí el motivo para seguir.',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Anular cobro'), findsOneWidget, reason: 'el botón dice Anular cobro');
      expect(elBoton(tester).onPressed, isNull, reason: 'apagado hasta elegir');
    });

    testWidgets('30B-03 · Motivo «Otro»', (tester) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(
        tester,
        m: MotivoDeAnulacion.otro,
        texto: 'El cliente pagó con transferencia',
      );
      expect(find.text('CONTANOS QUÉ PASÓ'), findsOneWidget);
      expect(find.text('El cliente pagó con transferencia'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNotNull);
      expect(find.text('Elegí el motivo para seguir.'), findsNothing);
    });

    testWidgets('30B-04 · Segunda confirmación', (tester) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      expect(find.text(r'¿Anular el cobro de $ 600?'), findsOneWidget);
      expect(
        find.text(
          r'El saldo de la venta vuelve a $ 1.200 y se resta $ 600 de tu dinero en mano. '
          'No se puede deshacer.',
        ),
        findsOneWidget,
      );
      expect(find.text('Sí, anular'), findsOneWidget);
      expect(find.text('No, volver'), findsOneWidget);
    });

    testWidgets('30B-05 · Anulado', (tester) async {
      await montarDetalleDelCobro(tester);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
      expect(find.text(r'Cobro anulado. El saldo volvió a $ 1.200.'), findsOneWidget);
      expect(botonAnularDelDetalle, findsNothing);
      expect(find.byKey(const Key('detalle_cobro_plazo')), findsNothing);
      expect(textoDe('cobro_saldo'), r'$ 1.200');
    });

    testWidgets('30B-06 · Pasaron las 72 h', (tester) async {
      await montarDetalleDelCobro(tester, ahora: DateTime.utc(2026, 10, 27));
      expect(
        find.text('Pasaron más de 72 h desde el cobro: ya no se puede anular.'),
        findsOneWidget,
      );
      expect(botonAnularDelDetalle, findsNothing);
      expect(find.byKey(const Key('detalle_cobro_plazo')), findsNothing);
    });

    testWidgets('30B-07 · Ticket validado (decisión del 23/10: «Pedíselo a tu coordinador»)', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria(cobros: [detalleDeEjemplo(medio: MedioCobranza.tarjeta)]);
      await montarDetalleDelCobro(tester, repo: repo, ticketValidado: true);
      expect(
        find.textContaining('El ticket de este cobro ya lo validó tu coordinador.'),
        findsOneWidget,
      );
      expect(find.textContaining('Pedíselo a tu coordinador'), findsOneWidget);
      expect(botonAnularDelDetalle, findsNothing, reason: 'Ana no anula sola');
    });

    testWidgets('30B-08 · Error al anular', (tester) async {
      final repo = AnulacionesEnMemoria()..fallas.add(const FailureCobroNoAnulado());
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
      expect(
        find.text('No pudimos anular el cobro. Sigue registrado como estaba.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget, reason: 'el botón pasa a «Reintentar»');
      expect(find.text('Anular cobro'), findsNothing);
      expect(
        elBoton(tester).onPressed,
        isNotNull,
        reason: 'lo elegido sigue y se puede reintentar',
      );
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('Los cinco estados del detalle', () {
    testWidgets('cargando: el esqueleto dice qué carga y no hay un spinner a secas', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final repo = AnulacionesEnMemoria()..compuertaDeLectura = Completer<void>();
      await montarDetalleDelCobro(tester, repo: repo);
      expect(find.bySemanticsLabel('Cargando el cobro'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Cobro'), findsWidgets, reason: 'el encabezado ya está');
      repo.compuertaDeLectura!.complete();
      await asentarAgendar(tester);
      expect(find.bySemanticsLabel('Cargando el cobro'), findsNothing);
      h.dispose();
      expect(find.text('Anular cobro'), findsOneWidget);
    });

    testWidgets('vacío: «el cobro ya no está» tiene salida (Volver)', (tester) async {
      final repo = AnulacionesEnMemoria(cobros: []);
      final a = await montarDetalleDelCobro(tester, repo: repo);
      expect(find.byKey(const Key('detalle_cobro_ausente')), findsOneWidget);
      await tocar(tester, find.text('Volver'));
      expect(paginaDetalle, findsNothing);
      expect(a.resultados, [false]);
    });

    testWidgets('error de lectura: aviso con «Reintentar» a mano y sin tocar nada más', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria()
        ..fallaDeLectura = const FailureCobroNoAnulado(causa: 'lectura')
        ..fallaDeLecturaUnaVez = true;
      await montarDetalleDelCobro(tester, repo: repo);
      expect(find.byKey(const Key('detalle_cobro_error_lectura')), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      await tocar(tester, find.text('Reintentar'));
      expect(find.text('Anular cobro'), findsOneWidget);
    });

    testWidgets('sin conexión: no hay estado propio, se anula igual en el teléfono', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria();
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.clienteEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Cliente equivocado');
      expect(_sinTocar('conexión'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('Validación de «Otro»', () {
    for (final vacio in {
      'vacío': '',
      'solo espacios': '      ',
      'espacios, tabs y saltos': ' \t\n \n\t ',
      'espacio de ancho cero y no separable': '​ ​',
    }.entries) {
      testWidgets('${vacio.key}: el botón queda apagado y la nota dice qué falta', (tester) async {
        final repo = AnulacionesEnMemoria();
        await montarDetalleDelCobro(tester, repo: repo);
        await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: vacio.value);
        expect(elBoton(tester).onPressed, isNull);
        expect(find.text('Contanos qué pasó para seguir.'), findsOneWidget);
        await tester.tap(botonPrincipal, warnIfMissed: false);
        await asentarAgendar(tester);
        expect(find.text('¿Anular el cobro de \$ 600?'), findsNothing);
        expect(repo.recibidos, isEmpty);
      });
    }

    testWidgets('emoji y caracteres especiales viajan tal cual', (tester) async {
      final repo = AnulacionesEnMemoria();
      await montarDetalleDelCobro(tester, repo: repo);
      const texto = r'Pagó 😀 con <b>"tarjeta"</b>; -- DROP TABLE cobranza; ñandú 🇺🇾';
      await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: texto);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
      expect(repo.recibidos.single.justificacion, texto);
    });

    testWidgets('texto pegado de 5.000 caracteres: el campo se queda en 200 y se anula', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria();
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: 'a' * 5000);
      expect(tester.widget<TextField>(campoOtro).controller!.text.length, 200);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
      expect(repo.recibidos.single.justificacion, 'a' * 200);
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Otro');
    });

    testWidgets('100 emoji (200 unidades UTF-16, justo el tope) se anulan', (tester) async {
      final repo = AnulacionesEnMemoria();
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: '😀' * 100);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
      expect(repo.recibidos, hasLength(1));
    });

    testWidgets(
      'el campo acepta 150 emoji (150 puntos de código ≤ 200) y entonces anular tiene que andar',
      (tester) async {
        final repo = AnulacionesEnMemoria();
        await montarDetalleDelCobro(tester, repo: repo);
        await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: '😀' * 150);
        await tocar(tester, botonPrincipal);
        await tocar(tester, siAnular);
        // El campo cuenta puntos de código (150) y el caso de uso cuenta unidades UTF-16 (300): lo que
        // el campo dejó escribir lo rechaza el caso de uso, y «Reintentar» falla igual para siempre.
        expect(repo.recibidos, hasLength(1), reason: 'el caso de uso rechazó un texto que cabe');
        expect(textoDe('detalle_cobro_estado'), 'Anulado · Otro');
      },
      // skip: QA #168: el campo «Otro» cuenta puntos de código y AnularCobroUseCase cuenta UTF-16:
      // de 101 a 200 emoji se escriben y la anulación falla sin salida.
      skip: !_hallazgos,
    );

    testWidgets('después de un error, lo tipeado en «Otro» no se pierde y el reintento lo manda', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria()..fallas.add(const FailureCobroNoAnulado());
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: 'Me equivoqué de cliente');
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);

      expect(find.byKey(const Key('anular_cobro_error')), findsOneWidget);
      expect(tester.widget<TextField>(campoOtro).controller!.text, 'Me equivoqué de cliente');
      expect(elBoton(tester).onPressed, isNotNull, reason: 'el botón vuelve a habilitarse');

      await tocar(tester, botonPrincipal);
      expect(repo.recibidos, hasLength(2));
      expect(repo.recibidos.last.justificacion, 'Me equivoqué de cliente');
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Otro');
    });

    testWidgets('volver de «Otro» a otro motivo no manda el texto escrito', (tester) async {
      final repo = AnulacionesEnMemoria();
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: 'no debería viajar');
      await tocar(tester, motivo(MotivoDeAnulacion.montoEquivocado));
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
      expect(repo.recibidos.single.justificacion, isNull);
      expect(repo.recibidos.single.motivo, MotivoDeAnulacion.montoEquivocado);
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('Casos límite de cada flujo', () {
    testWidgets('falla a mitad: el botón se rehabilita y nada queda «ocupado»', (tester) async {
      final repo = AnulacionesEnMemoria()
        ..fallas.addAll([const FailureCobroNoAnulado(), const FailureCobroNoAnulado()]);
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
      expect(find.text('Anulando…'), findsNothing);
      expect(elBoton(tester).onPressed, isNotNull);
      // Otra falla seguida: sigue sin trabarse.
      await tocar(tester, botonPrincipal);
      expect(find.text('Anulando…'), findsNothing);
      expect(elBoton(tester).onPressed, isNotNull);
      expect(find.byKey(const Key('venta_atras')), findsOneWidget, reason: 'se puede salir');
      // Y la tercera sale bien.
      await tocar(tester, botonPrincipal);
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
      expect(repo.recibidos, hasLength(3));
    });

    testWidgets('anulando: tocar otro motivo o la ✕ no cambia ni pierde el pedido en curso', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria()..compuerta = Completer<void>();
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);

      await tester.tap(motivo(MotivoDeAnulacion.clienteEquivocado), warnIfMissed: false);
      await asentarAgendar(tester);
      repo.compuerta!.complete();
      await asentarAgendar(tester);

      expect(repo.recibidos, hasLength(1));
      expect(repo.recibidos.single.motivo, MotivoDeAnulacion.montoEquivocado);
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
    });

    testWidgets('atrás del sistema con la hoja de confirmación abierta cierra solo la hoja', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria();
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      expect(siAnular, findsOneWidget);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(siAnular, findsNothing);
      expect(paginaAnular, findsOneWidget);
      expect(repo.recibidos, isEmpty);
      expect(elBoton(tester).onPressed, isNotNull, reason: 'lo elegido queda');
    });

    testWidgets('tocar fuera de la hoja la cierra sin anular', (tester) async {
      final repo = AnulacionesEnMemoria();
      await montarDetalleDelCobro(tester, repo: repo);
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      await tester.tapAt(const Offset(20, 20));
      await asentarAgendar(tester);
      expect(siAnular, findsNothing);
      expect(repo.recibidos, isEmpty);
    });

    testWidgets('atrás del sistema en el detalle sale con false y no anula', (tester) async {
      final repo = AnulacionesEnMemoria();
      final a = await montarDetalleDelCobro(tester, repo: repo);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(paginaDetalle, findsNothing);
      expect(a.resultados, [false]);
    });

    testWidgets('salir mientras todavía lee el cobro no revienta cuando la lectura termina', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria()..compuertaDeLectura = Completer<void>();
      final a = await montarDetalleDelCobro(tester, repo: repo);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(paginaDetalle, findsNothing);
      repo.compuertaDeLectura!.complete();
      await asentarAgendar(tester);
      expect(tester.takeException(), isNull);
      expect(a.resultados, [false]);
    });

    testWidgets('reentrar tres veces: cada vez lee de nuevo y no queda estado de antes', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria();
      await montarDetalleDelCobro(tester, repo: repo);
      for (var i = 0; i < 3; i++) {
        await irAAnular(tester, m: MotivoDeAnulacion.otro, texto: 'algo $i');
        await tester.binding.handlePopRoute(); // pregunta «¿Descartar?»
        await asentarAgendar(tester);
        await tocar(tester, find.text('Descartar'));
        await tocar(tester, find.byKey(const Key('venta_atras')));
        await abrirDetalle(tester);
      }
      expect(repo.lecturas, 4);
      expect(repo.recibidos, isEmpty);
      expect(find.text('Anular cobro'), findsOneWidget);
      await tocar(tester, botonAnularDelDetalle);
      expect(
        find.text('Elegí el motivo para seguir.'),
        findsOneWidget,
        reason: 'sin motivo de antes',
      );
      expect(find.text('CONTANOS QUÉ PASÓ'), findsNothing);
    });

    testWidgets(
      'si la relectura falla tras anular, el detalle ofrece «Reintentar» y queda anulado',
      (tester) async {
        final repo = AnulacionesEnMemoria();
        await montarDetalleDelCobro(tester, repo: repo);
        await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
        await tocar(tester, botonPrincipal);
        repo
          ..fallaDeLectura = const FailureCobroNoAnulado(causa: 'lectura')
          ..fallaDeLecturaUnaVez = true;
        await tocar(tester, siAnular);

        expect(repo.detalles['c-1']!.cobranza.estaAnulado, isTrue);
        expect(find.byKey(const Key('detalle_cobro_error_lectura')), findsOneWidget);
        await tocar(tester, find.text('Reintentar'));
        expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
      },
    );

    testWidgets('un cobro ya anulado pasadas las 72 h se muestra anulado, no «fuera de plazo»', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria(
        cobros: [
          detalleDeEjemplo(
            cobrado: 330000,
            anuladoAt: _fechaDelCobro.add(const Duration(hours: 2)),
            motivo: MotivoDeAnulacion.montoEquivocado,
          ),
        ],
      );
      await montarDetalleDelCobro(tester, repo: repo, ahora: DateTime.utc(2026, 11, 20));
      expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
      expect(find.textContaining('Pasaron más de 72 h'), findsNothing);
    });

    testWidgets('cobro anulado sin motivo guardado (dato viejo) dice solo «Anulado»', (
      tester,
    ) async {
      final repo = AnulacionesEnMemoria(
        cobros: [detalleDeEjemplo(cobrado: 330000, anuladoAt: _fechaDelCobro)],
      );
      await montarDetalleDelCobro(tester, repo: repo);
      expect(textoDe('detalle_cobro_estado'), 'Anulado');
    });

    testWidgets('con tarjeta y con transferencia la hoja resta del dinero depositado', (
      tester,
    ) async {
      for (final medio in [MedioCobranza.tarjeta, MedioCobranza.transferencia]) {
        final repo = AnulacionesEnMemoria(cobros: [detalleDeEjemplo(medio: medio)]);
        await montarDetalleDelCobro(tester, repo: repo);
        await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
        await tocar(tester, botonPrincipal);
        expect(find.textContaining('de tu dinero depositado'), findsOneWidget, reason: '$medio');
        await tocar(tester, noVolver);
        await tester.pumpWidget(const SizedBox());
      }
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'nombre de 150 letras, monto de nueve cifras y talonario largo en 360x640 x$escala',
        (tester) async {
          final largo = detalleDeEjemplo(
            monto: 99999999999,
            cobrado: 99999999999,
            cliente: 'María ' * 25,
          );
          final repo = AnulacionesEnMemoria(cobros: [largo]);
          await montarDetalleDelCobro(
            tester,
            repo: repo,
            escala: escala,
            tamano: const Size(360, 640),
          );
          expect(tester.takeException(), isNull);
          await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
          expect(tester.takeException(), isNull);
          await tocar(tester, botonPrincipal);
          expect(tester.takeException(), isNull);
          expect(siAnular, findsOneWidget);
          await tocar(tester, siAnular);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // ---------------------------------------------------------------------------------------------
  group('Saldo que dice la hoja de confirmación (30B-04) contra el que queda (30B-05)', () {
    testWidgets(
      'con una venta con devolución, «vuelve a X» es el saldo real tras anular',
      (tester) async {
        // Venta de $ 1.000, cobro único de $ 1.000 y una devolución de $ 400: hoy el saldo es 0 y, sin
        // el cobro, el cliente se queda con $ 600 y debe $ 600 (cuenta de `CuentaDeLaVenta`).
        final base = detalleDeEjemplo(monto: 100000, cobrado: 100000);
        final conDevolucion = DetalleDelCobro(
          cobranza: base.cobranza,
          venta: VentaConSaldo(
            ventaId: 'v-42',
            numeroTalonario: '0042',
            fecha: _ventaFecha,
            montoTotalCentavos: 100000,
            cobradoCentavos: 100000,
            devueltoCentavos: 40000,
          ),
          cliente: 'María Fernández',
        );
        final sinElCobro = VentaConSaldo(
          ventaId: 'v-42',
          numeroTalonario: '0042',
          fecha: _ventaFecha,
          montoTotalCentavos: 100000,
          cobradoCentavos: 0,
          devueltoCentavos: 40000,
        );
        expect(sinElCobro.saldoCentavos, 60000, reason: 'la cuenta real tras anular');

        await montarDetalleDelCobro(tester, repo: AnulacionesEnMemoria(cobros: [conDevolucion]));
        await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
        await tocar(tester, botonPrincipal);

        expect(find.textContaining(r'vuelve a $ 600 '), findsOneWidget);
        expect(find.textContaining(r'vuelve a $ 1.000 '), findsNothing);
      },
      // skip: QA #168: la hoja 30B-04 calcula min(saldo + cobro, total) e ignora las devoluciones
      // (FormatoAnulacion.saldoSinElCobro): dice $ 1.000 y el saldo real es $ 600.
      skip: !_hallazgos,
    );
  });

  // ---------------------------------------------------------------------------------------------
  group('Coherencia entre avisos', () {
    testWidgets(
      'ticket validado y pasadas las 72 h: no manda a «pedírselo al coordinador» si nadie puede anular',
      (tester) async {
        final repo = AnulacionesEnMemoria(cobros: [detalleDeEjemplo(medio: MedioCobranza.tarjeta)]);
        await montarDetalleDelCobro(
          tester,
          repo: repo,
          ahora: DateTime.utc(2026, 10, 27),
          ticketValidado: true,
        );
        expect(find.textContaining('Pasaron más de 72 h'), findsOneWidget);
        // Decisión del 23/10 («Anular 72 h»): pasado el plazo no anula nadie, tampoco el coordinador.
        expect(find.textContaining('Pedíselo a tu coordinador'), findsNothing);
      },
      // skip: QA #168: con el ticket validado y pasadas las 72 h el detalle dice «Pedíselo a tu
      // coordinador» y «ya no se puede anular» a la vez (decisión 23/10: nadie anula pasado el plazo).
      skip: !_hallazgos,
    );
  });

  // ---------------------------------------------------------------------------------------------
  group('Privacidad', () {
    test(
      'toString de las entidades y de las fallas no lleva el nombre del cliente ni lo escrito',
      () {
        final d = detalleDeEjemplo();
        final textos = [
          d.toString(),
          d.cobranza.toString(),
          d.venta.toString(),
          AnulacionHecha(detalle: d).toString(),
          const FailureCobroNoAnulado(causa: 'excepcion').toString(),
          const FailureAnulacionFueraDePlazo().toString(),
          const FailureAnulacionSinMotivo().toString(),
          const FailureCobroAusente().toString(),
          const AnularCobroParams(
            cobranzaId: 'c-1',
            colportorId: 'col-1',
            motivo: MotivoDeAnulacion.otro,
            justificacion: 'texto-privado',
          ).toString(),
        ];
        for (final t in textos) {
          expect(t, isNot(contains('María')), reason: t);
          expect(t, isNot(contains('Fernández')), reason: t);
          expect(t, isNot(contains('texto-privado')), reason: t);
        }
      },
    );
  });
}

final _ventaFecha = DateTime.utc(2026, 10, 12, 15);

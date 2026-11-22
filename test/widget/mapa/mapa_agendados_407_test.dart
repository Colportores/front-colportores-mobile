// La hoja «Agendados» del mapa (vista 06, 06C·03 «Hoja a 1/2 · Agendados (el mapa atenúa lo que no
// está agendado)», HU-VIS-002, #407): las visitas de la Agenda sobre el mapa, con sus chips de tipo,
// sus grupos por día, la cuota, el monto y la distancia, y el mapa que atenúa lo que no está agendado.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_agendados.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/ubicacion_colportor_falsos.dart';
import 'mapa_agendados_407_arnes.dart';
import 'mapa_ubicaciones_arnes.dart';

const _m = ' ';

void main() {
  group('06C·03 · Hoja a 1/2 · Agendados', () {
    testWidgets('la hoja ofrece «Agendados» con su cuenta junto a «Cercanía»', (tester) async {
      await montarAgendados(tester);
      final semantica = tester.ensureSemantics();

      expect(find.descendant(of: pestanaAgendados, matching: find.text('Agendados')), findsOne);
      expect(find.descendant(of: pestanaAgendados, matching: find.text('5')), findsOne);
      expect(
        find.descendant(
          of: find.byKey(ClavesMapaUbicaciones.pestanaCercania),
          matching: find.text('7'),
        ),
        findsOne,
      );
      expect(find.bySemanticsLabel('Agendados, 5 visitas'), findsOne);
      expect(find.bySemanticsLabel('Cercanía, 7 ubicaciones'), findsOne);
      // Minimizada, sin ninguna fila todavía.
      expect(fila407('cuota'), findsNothing);
      semantica.dispose();
    });

    testWidgets(
      'tocar «Agendados» con la hoja minimizada la sube y muestra los chips con su cuenta, '
      'los grupos ATRASADOS, HOY y MAÑANA y las visitas por hora',
      (tester) async {
        await montarAgendados(tester);
        final minimizada = altoHoja(tester);

        await abrirAgendados(tester);

        expect(altoHoja(tester), greaterThan(minimizada));
        for (final (tipo, texto, cuenta) in [
          (null, 'Todos', '5'),
          (TipoAgenda.cobranza, 'Cobranzas', '2'),
          (TipoAgenda.entrevista, 'Entrevistas', '2'),
          (TipoAgenda.entrega, 'Entregas', '1'),
        ]) {
          expect(find.descendant(of: chip407(tipo), matching: find.text(texto)), findsOne);
          expect(find.descendant(of: chip407(tipo), matching: find.text(cuenta)), findsOne);
        }

        expect(find.byKey(ClavesAgendados.atrasados), findsOne);
        expect(find.text('ATRASADOS'), findsOne);
        expect(find.text('HOY'), findsOne);
        expect(find.text('MAÑANA'), findsOne);
        final orden = [
          'atr',
          'cuota',
          'entrevista',
          'entrega',
          'manana',
        ].map((id) => tester.getTopLeft(fila407(id)).dy).toList();
        expect(orden, [...orden]..sort());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cada fila dice cuándo, a dónde, qué —con la cuota y lo que falta— y a cuánto está',
      (tester) async {
        await montarAgendados(tester);
        await abrirAgendados(tester);

        expect(filaDice('atr', 'Ayer'), isTrue);
        expect(filaDice('atr', 'Rivera 3920'), isTrue);
        expect(filaDice('atr', r'Cobranza atrasada · $U 980'), isTrue);
        expect(filaDice('atr', '240${_m}m'), isTrue);
        expect(filaDice('cuota', '15:00'), isTrue);
        expect(filaDice('cuota', 'Av. Italia 1234'), isTrue);
        expect(filaDice('cuota', r'Cobranza · 2.ª cuota · $U 1.450'), isTrue);
        expect(filaDice('cuota', '40${_m}m'), isTrue);
        expect(filaDice('entrevista', '16:30'), isTrue);
        expect(filaDice('entrevista', 'Comercio 2381'), isTrue);
        expect(filaDice('entrevista', 'Entrevista'), isTrue);
        expect(filaDice('entrevista', '90${_m}m'), isTrue);
        expect(filaDice('entrega', '18:00'), isTrue);
        expect(filaDice('entrega', 'Entrega y pago'), isTrue);
        expect(filaDice('entrega', '145${_m}m'), isTrue);
        expect(filaDice('manana', '10:00'), isTrue);
        expect(filaDice('manana', 'Mataojo 2044'), isTrue);
      },
    );

    testWidgets('la entrega de una venta ya pagada dice «Entrega pendiente», no «y pago»', (
      tester,
    ) async {
      await montarAgendados(
        tester,
        planes: {...planesDelCanvas(), 'v-michigan': planDe('v-michigan', cobrado: 290000)},
      );
      await abrirAgendados(tester);

      expect(filaDice('entrega', 'Entrega pendiente'), isTrue);
      expect(find.text('Entrega y pago'), findsNothing);
    });

    testWidgets('sin el plan de la venta la fila dice el tipo solo, sin inventar cuota ni monto', (
      tester,
    ) async {
      await montarAgendados(tester, planes: const {});
      await abrirAgendados(tester);

      expect(filaDice('cuota', 'Cobranza'), isTrue);
      expect(filaDice('atr', 'Cobranza atrasada'), isTrue);
      expect(filaDice('entrega', 'Entrega'), isTrue);
    });

    testWidgets('la atrasada de hace varios días lleva el día, no «Ayer»', (tester) async {
      await montarAgendados(
        tester,
        items: [agendado('vieja', dia407(9, dias: -5), ubicacionId: 'u-italia')],
      );
      await abrirAgendados(tester);

      final dia = dia407(9, dias: -5);
      final texto = '${dia.day.toString().padLeft(2, '0')}/${dia.month.toString().padLeft(2, '0')}';
      expect(filaDice('vieja', texto), isTrue);
      expect(filaDice('vieja', 'Entrevista atrasada'), isTrue);
    });

    testWidgets('los días después de mañana se rotulan con su nombre, con su cuenta', (
      tester,
    ) async {
      await montarAgendados(
        tester,
        items: [agendado('lejos', dia407(11, dias: 3), ubicacionId: 'u-italia')],
      );
      await abrirAgendados(tester);

      final dia = dia407(0, dias: 3);
      const dias = ['LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES', 'SÁBADO', 'DOMINGO'];
      expect(find.text('${dias[dia.weekday - 1]} ${dia.day}'), findsOne);
      expect(find.byKey(ClavesAgendados.dia(DateTime(dia.year, dia.month, dia.day))), findsOne);
    });
  });

  group('06C·03 · el mapa atenúa lo que no está agendado', () {
    testWidgets('con «Agendados» las casas sin visita se ven tenues; con «Cercanía», ninguna', (
      tester,
    ) async {
      final m = await montarAgendados(tester);
      final mapa = m.mapa.mapa;
      expect(mapa.config!.puntos.where((p) => p.atenuado), isEmpty);

      await abrirAgendados(tester);

      for (final id in ['u-rivera', 'u-italia', 'u-comercio', 'u-michigan', 'u-mataojo']) {
        expect(punto(mapa, id).atenuado, isFalse, reason: id);
      }
      expect(punto(mapa, 'u-1250').atenuado, isTrue);
      expect(punto(mapa, 'u-1236').atenuado, isTrue);
      expect(punto(mapa, 'gps').atenuado, isFalse);

      await tester.tap(find.byKey(ClavesMapaUbicaciones.pestanaCercania));
      await asentarLista(tester);
      expect(mapa.config!.puntos.where((p) => p.atenuado), isEmpty);
    });

    testWidgets('el chip de tipo filtra la lista y lo que el mapa deja vivo', (tester) async {
      final m = await montarAgendados(tester);
      await abrirAgendados(tester);

      await tocarChip(tester, TipoAgenda.cobranza);
      await asentarLista(tester);

      expect(fila407('atr'), findsOne);
      expect(fila407('cuota'), findsOne);
      expect(fila407('entrevista'), findsNothing);
      expect(fila407('entrega'), findsNothing);
      expect(find.text('MAÑANA'), findsNothing);
      expect(punto(m.mapa.mapa, 'u-italia').atenuado, isFalse);
      expect(punto(m.mapa.mapa, 'u-comercio').atenuado, isTrue);
      // Las cuentas de los chips no cambian con el filtro.
      expect(find.descendant(of: chip407(null), matching: find.text('5')), findsOne);
      final semantica = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byKey(ClavesAgendados.chip(TipoAgenda.cobranza))),
        isSemantics(isSelected: true, isButton: true, label: 'Cobranzas, 2'),
      );
      semantica.dispose();
    });

    testWidgets('la casa elegida nunca se atenúa, aunque no tenga nada agendado', (tester) async {
      final m = await montarAgendados(tester);
      await abrirAgendados(tester);

      m.mapa.mapa.tocarPunto('u-1250');
      await asentarLista(tester);

      expect(punto(m.mapa.mapa, 'u-1250').atenuado, isFalse);
      expect(punto(m.mapa.mapa, 'u-1236').atenuado, isTrue);
    });

    testWidgets('mientras se lee la agenda, o si falla, no se atenúa nada (no se sabe)', (
      tester,
    ) async {
      final consulta = ConsultaAgendaFalsa(agendaDelCanvas())..congelada = true;
      final m = await montarAgendados(tester, consulta: consulta);
      await abrirAgendados(tester);

      expect(find.byKey(ClavesAgendados.cargando), findsOne);
      expect(m.mapa.mapa.config!.puntos.where((p) => p.atenuado), isEmpty);
    });
  });

  group('estados de la hoja (los de la Agenda, #406)', () {
    testWidgets('vacía: «No tenés visitas en los próximos 7 días» con «+ Agendar», una sola vez '
        'aunque se toque dos veces', (tester) async {
      final m = await montarAgendados(tester, items: const [], conAgendar: true);
      await abrirAgendados(tester);

      expect(find.byKey(ClavesAgendados.vacia), findsOne);
      expect(find.text('No tenés visitas en los próximos 7 días'), findsOne);
      expect(find.descendant(of: pestanaAgendados, matching: find.text('0')), findsOne);
      final boton = find.text('+ Agendar');
      await tester.tap(boton);
      await tester.tap(boton);
      await asentarLista(tester);
      expect(m.agendados, 1);
      // Nada agendado: el mapa no tiene a dónde ir y todas se ven tenues.
      expect(
        m.mapa.mapa.config!.puntos.where((p) => p.id != 'gps').every((p) => p.atenuado),
        isTrue,
      );
    });

    testWidgets('vacía sin destino de «+ Agendar»: el texto, sin botón', (tester) async {
      await montarAgendados(tester, items: const []);
      await abrirAgendados(tester);

      expect(find.byKey(ClavesAgendados.vacia), findsOne);
      expect(find.text('+ Agendar'), findsNothing);
    });

    testWidgets('filtro sin resultados: «Ninguna agenda con estos filtros» y «Limpiar filtros» '
        'vuelve a «Todos»', (tester) async {
      await montarAgendados(
        tester,
        items: [
          for (final i in agendaDelCanvas())
            if (i.agenda.tipo != TipoAgenda.entrega) i,
        ],
      );
      await abrirAgendados(tester);

      await tocarChip(tester, TipoAgenda.entrega);
      await asentarLista(tester);
      expect(find.byKey(ClavesAgendados.sinResultados), findsOne);
      expect(find.text('Ninguna agenda con estos filtros'), findsOne);
      expect(fila407('cuota'), findsNothing);

      await tester.tap(find.text('Limpiar filtros'));
      await asentarLista(tester);
      expect(fila407('cuota'), findsOne);
      expect(find.byKey(ClavesAgendados.sinResultados), findsNothing);
    });

    testWidgets('error al leer: «No pudimos leer tu agenda.» y «Reintentar» vuelve a leer', (
      tester,
    ) async {
      final consulta = ConsultaAgendaFalsa(agendaDelCanvas())..error = Exception('db');
      final m = await montarAgendados(tester, consulta: consulta);
      await abrirAgendados(tester);

      expect(find.byKey(ClavesAgendados.error), findsOne);
      expect(find.text('No pudimos leer tu agenda.'), findsOne);
      // Sin cuenta: no se sabe cuántas hay.
      expect(find.descendant(of: pestanaAgendados, matching: find.text('5')), findsNothing);
      expect(m.mapa.mapa.config!.puntos.where((p) => p.atenuado), isEmpty);
      final pedidos = consulta.pedidos.length;

      consulta.error = null;
      await tester.tap(find.text('Reintentar'));
      await asentarLista(tester);

      expect(consulta.pedidos.length, greaterThan(pedidos));
      expect(find.byKey(ClavesAgendados.error), findsNothing);
      expect(fila407('cuota'), findsOne);
    });

    testWidgets('un error después de los datos también se dice (no queda una lista vieja)', (
      tester,
    ) async {
      final m = await montarAgendados(tester);
      await abrirAgendados(tester);
      expect(fila407('cuota'), findsOne);

      m.consulta.emitirError(Exception('db'));
      await asentarLista(tester);

      expect(find.byKey(ClavesAgendados.error), findsOne);
      expect(fila407('cuota'), findsNothing);
    });

    testWidgets('cargando: el esqueleto de la Agenda y la pestaña sin cuenta', (tester) async {
      final consulta = ConsultaAgendaFalsa(agendaDelCanvas())..congelada = true;
      await montarAgendados(tester, consulta: consulta);
      await abrirAgendados(tester);

      expect(find.byKey(ClavesAgendados.cargando), findsOne);
      expect(find.descendant(of: pestanaAgendados, matching: find.text('5')), findsNothing);
    });

    testWidgets('reactiva: una visita que se agenda aparece sola, con su cuenta y su casa viva', (
      tester,
    ) async {
      final m = await montarAgendados(tester);
      await abrirAgendados(tester);
      expect(punto(m.mapa.mapa, 'u-1250').atenuado, isTrue);

      m.consulta.emitir([
        ...agendaDelCanvas(),
        agendado('nueva', dia407(19), ubicacionId: 'u-1250', numero: '1250', metros: 300),
      ]);
      await asentarLista(tester);

      expect(fila407('nueva'), findsOne);
      expect(find.descendant(of: pestanaAgendados, matching: find.text('6')), findsOne);
      expect(punto(m.mapa.mapa, 'u-1250').atenuado, isFalse);
    });
  });

  group('tocar una visita abre su detalle (HU-VIS-003)', () {
    testWidgets('una fila abre el detalle de su agenda', (tester) async {
      final m = await montarAgendados(tester);
      await abrirAgendados(tester);

      await tocarFila(tester, 'cuota');
      await asentarLista(tester);

      expect(m.detalles, ['cuota']);
    });

    testWidgets('doble toque: un solo detalle', (tester) async {
      final m = await montarAgendados(tester);
      m.esperaDetalle = Completer<void>();
      await abrirAgendados(tester);

      await tocarFila(tester, 'cuota');
      await tocarFila(tester, 'cuota');
      await asentarLista(tester);
      m.esperaDetalle!.complete();
      await asentarLista(tester);

      expect(m.detalles, ['cuota']);
    });

    testWidgets(
      'dos filas seguidas mientras el primero sigue abierto: solo el primero; al volver se '
      'puede abrir otro',
      (tester) async {
        final m = await montarAgendados(tester);
        m.esperaDetalle = Completer<void>();
        await abrirAgendados(tester);

        await tocarFila(tester, 'cuota');
        await asentarLista(tester, 2);
        await tocarFila(tester, 'entrevista');
        await asentarLista(tester, 2);
        expect(m.detalles, ['cuota']);

        m.esperaDetalle!.complete();
        m.esperaDetalle = null;
        await asentarLista(tester);
        await tocarFila(tester, 'entrevista');
        await asentarLista(tester);
        expect(m.detalles, ['cuota', 'entrevista']);
      },
    );

    testWidgets('si el detalle falla se avisa y la fila se puede volver a tocar', (tester) async {
      final m = await montarAgendados(tester);
      m.fallaDetalle = StateError('no abre');
      await abrirAgendados(tester);

      await tocarFila(tester, 'cuota');
      await asentarLista(tester);
      expect(find.text('No pudimos abrir eso. Probá de nuevo.'), findsOne);

      m.fallaDetalle = null;
      await tocarFila(tester, 'cuota');
      await asentarLista(tester);
      expect(m.detalles, ['cuota', 'cuota']);
    });

    testWidgets('sin destino del detalle las filas no son botones', (tester) async {
      final m = await montarAgendados(tester, conDetalle: false);
      await abrirAgendados(tester);
      final semantica = tester.ensureSemantics();

      expect(
        tester.getSemantics(fila407('cuota')),
        isSemantics(isButton: false, hasTapAction: false),
      );
      await tocarFila(tester, 'cuota');
      await asentarLista(tester);
      expect(m.detalles, isEmpty);
      semantica.dispose();
    });

    testWidgets('el lector lee la fila entera', (tester) async {
      await montarAgendados(tester);
      await abrirAgendados(tester);
      final semantica = tester.ensureSemantics();

      expect(
        find.bySemanticsLabel(
          '15:00. Av. Italia 1234. Cobranza · 2.ª cuota · \$U 1.450. a 40${_m}m',
        ),
        findsOne,
      );
      semantica.dispose();
    });
  });

  group('la distancia sale del GPS al abrir la hoja', () {
    testWidgets('caminar con la hoja abierta no la cambia; al volver a abrirla, sí', (
      tester,
    ) async {
      final gps = GpsFalso();
      await montarAgendados(tester, gps: gps);
      await abrirAgendados(tester);
      expect(filaDice('cuota', '40${_m}m'), isTrue);

      gps.respuesta = Right(lecturaGps(6, punto: alNorte(-100)));
      await refrescarGpsDelColportor(tester);
      await asentarLista(tester);
      expect(filaDice('cuota', '40${_m}m'), isTrue);

      // Minimizar y volver a abrir: se mide desde donde está ahora (140 m).
      await tocarAsa(tester);
      await tester.tap(pestanaAgendados);
      await asentarLista(tester);
      expect(filaDice('cuota', '140${_m}m'), isTrue);
    });

    testWidgets('sin GPS no hay distancia; la primera lectura que llega la completa', (
      tester,
    ) async {
      final gps = GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal)));
      await montarAgendados(tester, gps: gps);
      await abrirAgendados(tester);
      expect(filaDice('cuota', '40${_m}m'), isFalse);
      expect(filaDice('cuota', 'Av. Italia 1234'), isTrue);

      gps.respuesta = Right(lecturaGps(6));
      await refrescarGpsDelColportor(tester);
      await asentarLista(tester);
      expect(filaDice('cuota', '40${_m}m'), isTrue);
    });
  });

  group('decisiones del 11/11 (QA de #704)', () {
    testWidgets('P2 · «Agendados» sube la hoja a la mitad; «Cercanía», minimizada, a un tercio', (
      tester,
    ) async {
      await montarAgendados(tester, tamano: const Size(360, 640));
      final minimizada = altoHoja(tester);

      await abrirAgendados(tester);
      final mitad = altoHoja(tester);
      expect(mitad, greaterThan(minimizada));
      // Desde la mitad el asa vuelve a la minimizada (a un tercio subiría a la mitad).
      await tocarAsa(tester);
      expect(altoHoja(tester), minimizada);

      await tester.tap(find.byKey(ClavesMapaUbicaciones.pestanaCercania));
      await asentarLista(tester);
      final tercio = altoHoja(tester);
      expect(tercio, greaterThan(minimizada));
      expect(tercio, lessThan(mitad));

      // Ya a un tercio, «Agendados» la sube a la mitad.
      await tester.tap(pestanaAgendados);
      await asentarLista(tester);
      expect(altoHoja(tester), mitad);
    });

    testWidgets(
      'P1 · los chips van en una sola fila que se desplaza y el elegido queda a la vista',
      (tester) async {
        await montarAgendados(tester, tamano: const Size(360, 640));
        await abrirAgendados(tester);

        final tops = {
          for (final tipo in [null, ...TipoAgenda.values])
            tester.getCenter(chip407(tipo)).dy.round(),
        };
        expect(tops, hasLength(1), reason: 'los cuatro chips en un mismo renglón');

        await tocarChip(tester, TipoAgenda.entrega);
        await asentarLista(tester);
        final rect = tester.getRect(chip407(TipoAgenda.entrega));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(fila407('entrega'), findsOne);

        // Al volver a la hoja con «Entregas» elegido, el chip sigue a la vista.
        await tester.tap(find.byKey(ClavesMapaUbicaciones.pestanaCercania));
        await asentarLista(tester);
        await tester.tap(pestanaAgendados);
        await asentarLista(tester);
        expect(tester.getRect(chip407(TipoAgenda.entrega)).right, lessThanOrEqualTo(360));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('volver atrás y reentrar', () {
    testWidgets('el chip elegido se conserva al pasar por «Cercanía» y al cambiar de pestaña de la '
        'app', (tester) async {
      final m = await montarAgendados(tester);
      await abrirAgendados(tester);
      await tocarChip(tester, TipoAgenda.entrevista);
      await asentarLista(tester);

      await tester.tap(find.byKey(ClavesMapaUbicaciones.pestanaCercania));
      await asentarLista(tester);
      expect(fila407('cuota'), findsNothing);
      expect(fila('u-italia'), findsOne);

      m.mapa.activa.value = false;
      await asentarLista(tester);
      m.mapa.activa.value = true;
      await asentarLista(tester);

      await tester.tap(pestanaAgendados);
      await asentarLista(tester);
      expect(fila407('entrevista'), findsOne);
      expect(fila407('cuota'), findsNothing);
    });

    testWidgets('tocar una casa abre su hoja y cerrarla vuelve a «Agendados»', (tester) async {
      final m = await montarAgendados(tester);
      await abrirAgendados(tester);

      m.mapa.mapa.tocarPunto('u-italia');
      await asentarLista(tester);
      expect(fila407('cuota'), findsNothing);

      await tester.tap(cerrarVistaPrevia);
      await asentarLista(tester);
      expect(fila407('cuota'), findsOne);
    });

    testWidgets('dos chips seguidos sin esperar: queda el último', (tester) async {
      await montarAgendados(tester);
      await abrirAgendados(tester);

      // «Cobranzas» y enseguida «Todos», sin dejar correr un cuadro: gana el último.
      await tester.tap(chip407(TipoAgenda.cobranza));
      await tester.tap(chip407(null));
      await asentarLista(tester);

      expect(fila407('entrega'), findsOne);
      expect(fila407('cuota'), findsOne);
    });
  });

  group('datos límite', () {
    testWidgets('una lista larga se desplaza hasta la última visita', (tester) async {
      await montarAgendados(
        tester,
        tamano: const Size(390, 844),
        items: [
          for (var i = 0; i < 60; i++)
            agendado(
              'v$i',
              dia407(8, dias: i % 8, minuto: i),
              ubicacionId: 'u-italia',
              numero: '${1000 + i}',
            ),
        ],
      );
      await abrirAgendados(tester);

      await tester.scrollUntilVisible(fila407('v59'), 300, scrollable: listaDeAgendados);
      expect(fila407('v59'), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una dirección larguísima no desborda', (tester) async {
      await montarAgendados(
        tester,
        tamano: const Size(320, 568),
        items: [
          agendado(
            'larga',
            dia407(17),
            tipo: TipoAgenda.cobranza,
            ubicacionId: 'u-italia',
            calle: 'Avenida Doctor Luis Alberto de Herrera esquina Bulevar General Artigas',
            numero: '12345 bis',
            ventaId: 'v-italia',
            montoPrevisto: 145000,
          ),
        ],
      );
      await abrirAgendados(tester);
      await verFila(tester, 'larga');

      expect(fila407('larga'), findsOne);
      expect(tester.takeException(), isNull);
    });

    for (final tamano in const [Size(320, 568), Size(390, 844)]) {
      testWidgets('con el texto al 200 % (${tamano.width.toInt()}×${tamano.height.toInt()}) las '
          'pestañas, los chips y las filas entran sin desbordar', (tester) async {
        await montarAgendados(tester, escala: 2, tamano: tamano);
        await abrirAgendados(tester);
        expect(tester.takeException(), isNull);

        expect(chip407(TipoAgenda.entrega), findsOne);
        // El chip mide al menos 48 dp de alto (objetivo táctil).
        expect(tester.getSize(chip407(TipoAgenda.cobranza)).height, greaterThanOrEqualTo(48));
        final lista = listaDeAgendados;
        await tester.scrollUntilVisible(fila407('manana'), 200, scrollable: lista);
        expect(fila407('manana'), findsOne);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('la hoja no mide más que su tope con la lista larga', (tester) async {
      await montarAgendados(
        tester,
        tamano: const Size(390, 844),
        items: [
          for (var i = 0; i < 30; i++)
            agendado('v$i', dia407(9, minuto: i), ubicacionId: 'u-italia'),
        ],
      );
      await abrirAgendados(tester);

      expect(find.byType(HojaMapaUbicaciones), findsOne);
      expect(altoHoja(tester), lessThanOrEqualTo(844 * .7));
      expect(tester.takeException(), isNull);
    });
  });
}

// «Vender» desde la casa deja también una visita «Venta» de hoy (vista 39; #669): la decisión de Cristian del
// 05/11, «Vender visita» («Sí, una visita «Venta» de hoy»). La visita va en la misma transacción que la
// venta (R44): o se guardan las dos o ninguna. La jornada la cuenta (lleva su id) y la casa recalcula el
// color. Con los ganchos enchufados a los flujos reales, como los enchufa `main.dart`.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/agenda/domain/services/destino_de_entrevista.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrevista_dada_648_arnes.dart';

final _ayer = DateTime.utc(2026, 10, 22, 15);

/// Una jornada abierta hoy (el reloj del arnés marca el 23/10 a las 14:41).
JornadaModel _jornada(String id, {String colportorId = 'col-1'}) {
  final inicio = DateTime.utc(2026, 10, 23, 12);
  return JornadaModel(
    id: id,
    colportorId: colportorId,
    inicio: inicio,
    auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: colportorId),
  );
}

Finder get _ventaPagina => find.byKey(const Key('nueva_venta_pagina'));
Finder get _vender => find.byKey(ClavesQuePaso.opcion(OpcionQuePaso.vender));

/// «¿Qué pasó?» → «Vender» → la venta con el pack fijo, lista para «Registrar».
Future<void> _hastaLaVenta(WidgetTester tester, Arnes648 a, {String numero = '0039'}) async {
  await a.abrirQuePaso(tester);
  await a.elegir(tester, OpcionQuePaso.vender);
  await a.armarLaVenta(tester, numero: numero);
}

void main() {
  late Arnes648 a;

  setUp(() {
    a = Arnes648();
    a.lector.porVinculo['ep-1'] = _ayer;
  });

  group('la venta y su visita «Venta» de hoy, juntas', () {
    testWidgets(
      'al registrar, la venta lleva el id de la visita y la visita es «Venta» de esa persona',
      (tester) async {
        await a.montar(tester);
        await _hastaLaVenta(tester, a);
        expect(a.montaje.agenda.recibidas, isEmpty, reason: 'hasta registrar no se guarda nada');

        await a.registrarSinFecha(tester);

        final visita = a.montaje.agenda.recibidas.single.visita;
        expect(visita.tipoResultado, TipoResultadoVisita.venta);
        expect(visita.espacioId, 'esp-1');
        expect(visita.espacioPersonaId, 'ep-1');
        expect(visita.colportorId, 'col-1');
        final venta = a.entorno.ventas.recibidas.single.venta;
        expect(venta.visitaId, visita.id);
        expect(a.salidasDeVenta.single, isA<VentaRegistradaEnLaCasa>());
        expect(a.resultados, [true], reason: 'tras guardar (05/11): la hoja de la casa se cierra');
        expect(
          a.montaje.almacen.guardadas,
          isEmpty,
          reason: 'no hay entrevista en curso que cerrar',
        );
      },
    );

    testWidgets('la visita lleva la jornada abierta, así la jornada la cuenta', (tester) async {
      await a.montar(tester);
      await a.jornadas.insertar(_jornada('jor-1'));
      await _hastaLaVenta(tester, a);

      await a.registrarSinFecha(tester);

      expect(a.montaje.agenda.recibidas.single.visita.jornadaId, 'jor-1');
      expect(a.ventas.single.jornadaId, 'jor-1');
    });

    testWidgets('sin jornada abierta la visita va sin jornada (nunca se inventa una)', (
      tester,
    ) async {
      await a.montar(tester);
      await _hastaLaVenta(tester, a);

      await a.registrarSinFecha(tester);

      expect(a.montaje.agenda.recibidas.single.visita.jornadaId, isNull);
    });

    testWidgets('la jornada de otra colportora no se le cuelga', (tester) async {
      await a.montar(tester);
      await a.jornadas.insertar(_jornada('jor-ajena', colportorId: 'col-2'));
      await _hastaLaVenta(tester, a);

      await a.registrarSinFecha(tester);

      expect(a.montaje.agenda.recibidas.single.visita.jornadaId, isNull);
    });

    testWidgets('desde una fila de la agenda, la visita «Venta» cumple esa agenda', (tester) async {
      await a.montar(tester, agendaId: 'ag-7');
      await _hastaLaVenta(tester, a);

      await a.registrarSinFecha(tester);

      expect(a.montaje.agenda.recibidas.single.agendaId, 'ag-7');
      expect(a.ventas.single.agendaId, 'ag-7');
    });

    testWidgets('si la venta no se guarda, no queda la visita; el reintento guarda una sola', (
      tester,
    ) async {
      await a.montar(tester);
      a.entorno.ventas.respuesta = const FailureInesperado();
      await _hastaLaVenta(tester, a);

      await a.tocarKey(tester, const Key('venta_cta'));

      expect(_ventaPagina, findsOneWidget);
      expect(a.salidasDeVenta, isEmpty);
      expect(a.montaje.agenda.recibidas, isEmpty, reason: 'R44: la visita no queda sin su venta');

      a.entorno.ventas.respuesta = null;
      await a.registrarSinFecha(tester);

      expect(a.montaje.agenda.recibidas, hasLength(1));
      expect(a.salidasDeVenta.single, isA<VentaRegistradaEnLaCasa>());
    });

    testWidgets('si la visita no se guarda, la venta tampoco; el reintento usa la misma visita', (
      tester,
    ) async {
      await a.montar(tester);
      await _hastaLaVenta(tester, a);
      a.montaje.agenda.falla = const FailureInesperado();

      await a.tocarKey(tester, const Key('venta_cta'));

      expect(_ventaPagina, findsOneWidget, reason: 'el botón vuelve a quedar habilitado');
      expect(a.salidasDeVenta, isEmpty);
      expect(a.montaje.agenda.recibidas, isEmpty);

      a.montaje.agenda.falla = null;
      await a.registrarSinFecha(tester);

      final visita = a.montaje.agenda.recibidas.single.visita;
      expect(a.entorno.ventas.recibidas.last.venta.visitaId, visita.id);
      expect(a.salidasDeVenta.single, isA<VentaRegistradaEnLaCasa>());
    });

    testWidgets('salir de la venta sin guardar no deja ninguna visita ni avisa', (tester) async {
      await a.montar(tester);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);

      await a.tocarKey(tester, const Key('venta_atras'));

      expect(a.montaje.agenda.recibidas, isEmpty);
      expect(a.entorno.ventas.recibidas, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(a.resultados, isEmpty, reason: '«¿Qué pasó?» sigue abierta');
      expect(_vender, findsOneWidget);
    });

    testWidgets('volver atrás y reentrar a «Vender»: una sola visita al final', (tester) async {
      await a.montar(tester);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
      await a.tocarKey(tester, const Key('venta_atras'));

      await a.elegir(tester, OpcionQuePaso.vender);
      await a.armarLaVenta(tester);
      await a.registrarSinFecha(tester);

      expect(a.montaje.agenda.recibidas, hasLength(1));
      expect(a.entorno.ventas.recibidas, hasLength(1));
    });

    testWidgets('dos ventas seguidas: cada una con su visita, ninguna se pisa', (tester) async {
      await a.montar(tester);
      await _hastaLaVenta(tester, a, numero: '0039');
      await a.registrarSinFecha(tester);
      await _hastaLaVenta(tester, a, numero: '0040');
      await a.registrarSinFecha(tester);

      final visitas = a.montaje.agenda.recibidas.map((r) => r.visita).toList();
      expect(visitas, hasLength(2));
      expect(visitas.map((v) => v.id).toSet(), hasLength(2));
      expect(visitas.map((v) => v.tipoResultado).toSet(), {TipoResultadoVisita.venta});
      final ventas = a.entorno.ventas.recibidas.map((r) => r.venta).toList();
      expect(ventas.map((v) => v.visitaId), visitas.map((v) => v.id));
    });

    testWidgets('doble toque en «Vender»: una sola venta abierta y una sola visita', (
      tester,
    ) async {
      await a.montar(tester);
      await a.abrirQuePaso(tester);
      final renglon = _vender;
      await tester.ensureVisible(renglon);
      await tester.pump();
      await tester.tap(renglon);
      await tester.tap(renglon, warnIfMissed: false);
      await a.asentar(tester);
      await a.armarLaVenta(tester);

      await a.registrarSinFecha(tester);

      expect(a.ventas, hasLength(1));
      expect(a.montaje.agenda.recibidas, hasLength(1));
    });
  });

  group('la persona o la casa cambiaron mientras tanto: se dice por qué y no se guarda nada', () {
    testWidgets('la persona se dio de baja: aviso con qué hacer, «¿Qué pasó?» sigue abierta', (
      tester,
    ) async {
      await a.montar(tester);
      await a.abrirQuePaso(tester);
      a.montaje.destino.destino = const DestinoDeEntrevista(espacioId: 'esp-1');

      await a.elegir(tester, OpcionQuePaso.vender);

      expect(_ventaPagina, findsNothing);
      expect(
        find.text(
          'La venta no se guardó. Esa persona ya no está en tu teléfono, así que no se puede '
          'registrar la venta. Elegí otra opción.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('entrevista sigue en curso'), findsNothing);
      expect(a.montaje.agenda.recibidas, isEmpty);
      expect(a.entorno.ventas.recibidas, isEmpty);
      expect(a.resultados, isEmpty);
      expect(_vender, findsOneWidget, reason: 'se puede elegir otra cosa');
      expect(find.byKey(ClavesQuePaso.guardando), findsNothing);
    });

    testWidgets('la casa ya no está en el teléfono: aviso con qué hacer y nada se guarda', (
      tester,
    ) async {
      await a.montar(tester);
      await a.abrirQuePaso(tester);
      a.montaje.destino.sinDestino = true;

      await a.elegir(tester, OpcionQuePaso.vender);

      expect(_ventaPagina, findsNothing);
      expect(
        find.text(
          'La venta no se guardó. La casa ya no está en tu teléfono, así que no se puede '
          'registrar la venta. Elegí otra opción.',
        ),
        findsOneWidget,
      );
      expect(a.montaje.agenda.recibidas, isEmpty);
      expect(a.resultados, isEmpty);
    });

    testWidgets('si no se puede leer dónde cuelga la venta, el aviso común y se puede reintentar', (
      tester,
    ) async {
      await a.montar(tester);
      await a.abrirQuePaso(tester);
      a.montaje.destino.falla = true;

      await a.elegir(tester, OpcionQuePaso.vender);

      expect(_ventaPagina, findsNothing);
      expect(find.textContaining('La venta no se guardó'), findsOneWidget);
      expect(a.montaje.agenda.recibidas, isEmpty);

      a.montaje.destino.falla = false;
      await a.elegir(tester, OpcionQuePaso.vender);
      expect(_ventaPagina, findsOneWidget);
    });
  });

  group('datos límite', () {
    testWidgets('textScaler 2.0: «Vender» abre la venta y no desborda', (tester) async {
      await a.montar(tester, escala: 2, tamano: const Size(360, 640));
      await a.abrirQuePaso(tester);

      await a.elegir(tester, OpcionQuePaso.vender);

      expect(tester.takeException(), isNull);
      expect(_ventaPagina, findsOneWidget);
      expect(a.montaje.agenda.recibidas, isEmpty, reason: 'hasta registrar no se guarda nada');
    });

    testWidgets(
      'textScaler 2.0: el aviso de la persona dada de baja se lee entero y sin desbordar',
      (tester) async {
        await a.montar(tester, escala: 2, tamano: const Size(360, 640));
        await a.abrirQuePaso(tester);
        a.montaje.destino.destino = const DestinoDeEntrevista(espacioId: 'esp-1');

        await a.elegir(tester, OpcionQuePaso.vender);

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Esa persona ya no está en tu teléfono'), findsOneWidget);
        expect(_vender, findsOneWidget);
      },
    );
  });
}

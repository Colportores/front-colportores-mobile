// «Entrevista dada» (R·04 → R·05) y «Vender» de «¿Qué pasó?» (vista 39; #648): de «✓ Registrar visita» de
// la hoja de la casa a la entrevista en curso, a «¿Hubo venta?», a la venta, a «¿Cuándo volvés a cobrar?»
// y a R·08, con los ganchos enchufados a los flujos reales como los enchufa `main.dart`.
//
// «Vender» es la decisión de Cristian del 04/11 («Vender desde el mapa»): solo se ofrece si la casa ya
// tuvo una entrevista dada, y no es parte del canvas R·01.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrevista_dada_648_arnes.dart';
import '../../helpers/entrevista_falsos.dart';
import '../../helpers/persona_falsos.dart';

final _ayer = DateTime.utc(2026, 10, 22, 15);
final _hoy = DateTime.utc(2026, 10, 23, 12);

Finder get _vender => find.byKey(ClavesQuePaso.opcion(OpcionQuePaso.vender));
Finder get _ventaPagina => find.byKey(const Key('nueva_venta_pagina'));

void main() {
  late Arnes648 a;

  setUp(() => a = Arnes648());

  group('«Entrevista dada» → R·05 «Entrevista en curso»', () {
    testWidgets('«Empezar» guarda la entrevista con la hora del toque y abre R·05', (tester) async {
      await a.montar(tester);

      await a.hastaLaEntrevista(tester);

      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
      final guardada = a.montaje.almacen.guardadas['col-1']!;
      expect(guardada.espacioId, 'esp-1');
      expect(guardada.espacioPersonaId, 'ep-1');
      expect(guardada.inicio.isAtSameMomentAs(ahoraEntrevista), isTrue);
      expect(a.entrevistas.single.persona.espacioPersonaId, 'ep-1');
      expect(a.entrevistas.single.ubicacionId, 'ub-1');
      expect(a.resultados, isEmpty, reason: '«¿Qué pasó?» sigue esperando a que R·05 se resuelva');
    });

    testWidgets('con la jornada o la agenda de la fila, la entrevista las lleva', (tester) async {
      await a.montar(tester, agendaId: 'ag-7');

      await a.hastaLaEntrevista(tester);

      expect(a.montaje.almacen.guardadas['col-1']!.agendaId, 'ag-7');
      expect(a.entrevistas.single.agendaId, 'ag-7');
    });

    testWidgets(
      'cerrar R·05 la deja en curso: aviso fijo en el mapa y la hoja de la casa se cierra',
      (tester) async {
        await a.montar(tester);
        await a.hastaLaEntrevista(tester);

        await tester.binding.handlePopRoute();
        await a.asentar(tester);

        expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsNothing);
        expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
        expect(a.montaje.almacen.guardadas, hasLength(1));
        expect(a.montaje.agenda.recibidas, isEmpty);
        expect(a.resultados, [true]);
        expect(a.salidasDeEntrevista, [true]);
      },
    );

    testWidgets(
      'R·06 «No, guardar y volver al mapa» guarda la visita ENTREVISTA y cierra la entrevista',
      (tester) async {
        await a.montar(tester);
        await a.hastaLaHoraDeSalida(tester);

        expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
        await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

        final visita = a.montaje.agenda.recibidas.single.visita;
        expect(visita.tipoResultado, TipoResultadoVisita.entrevista);
        expect(visita.espacioPersonaId, 'ep-1');
        expect(a.montaje.almacen.guardadas, isEmpty);
        expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);
        expect(a.resultados, [
          true,
        ], reason: 'la hoja de la casa se cierra: el mapa pinta el color nuevo');
        expect(a.salidasDeEntrevista.single, isNot(isA<VentaRegistradaEnLaCasa>()));
      },
    );

    testWidgets('R·06 «Sí, registrar la venta» abre la venta con la casa y la persona puestas', (
      tester,
    ) async {
      await a.montar(tester);
      await a.hastaLaHoraDeSalida(tester);

      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);

      expect(_ventaPagina, findsOneWidget);
      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
      expect(a.montaje.agenda.recibidas, isEmpty, reason: 'R44: nada se guarda hasta la venta');
      expect(a.montaje.almacen.guardadas, hasLength(1));
    });

    testWidgets(
      'la cadena completa: venta → «¿Cuándo volvés a cobrar?» → R·08 con la hoja abierta',
      (tester) async {
        await a.montar(tester);
        await a.hastaLaVenta(tester);

        await a.registrarSinFecha(tester);

        final visita = a.montaje.agenda.recibidas.single.visita;
        expect(visita.tipoResultado, TipoResultadoVisita.venta);
        final venta = a.entorno.ventas.recibidas.single.venta;
        expect(
          venta.visitaId,
          visita.id,
          reason: 'la venta lleva el id de la visita de la entrevista',
        );
        expect(venta.numeroTalonario, '0039');
        expect(a.montaje.almacen.guardadas, isEmpty);
        expect(a.salidasDeEntrevista.single, isA<VentaRegistradaEnLaCasa>());
        expect(
          a.resultados,
          [false],
          reason: 'R·08: la hoja de la casa queda abierta, no se cierra ni se deselecciona la casa',
        );
        expect(find.text('Venta 0039 guardada.'), findsOneWidget);
      },
    );

    testWidgets('salir de la venta sin guardar deja la entrevista en curso y la hoja se cierra', (
      tester,
    ) async {
      await a.montar(tester);
      await a.hastaLaHoraDeSalida(tester);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);

      await a.tocarKey(tester, const Key('venta_atras'));

      expect(a.entorno.ventas.recibidas, isEmpty);
      expect(a.montaje.agenda.recibidas, isEmpty);
      expect(a.montaje.almacen.guardadas, hasLength(1));
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
      expect(a.resultados, [true]);
    });
  });

  group('R·07: «Empezar» no se pudo guardar', () {
    testWidgets('sigue «Terminó la entrevista» sin inicio registrado y se guarda igual', (
      tester,
    ) async {
      a.montaje.rota.fallaAlGuardar = true;
      a.montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 13, 30);
      await a.montar(tester);

      await a.hastaLaEntrevista(tester);

      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsNothing);
      expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
      expect(find.byKey(ClavesEntrevista.avisoSinInicio), findsOneWidget);

      await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

      expect(
        a.montaje.agenda.recibidas.single.visita.tipoResultado,
        TipoResultadoVisita.entrevista,
      );
      expect(a.resultados, [true]);
    });

    testWidgets('cerrar R·07 sin guardar no deja nada y «¿Qué pasó?» se puede volver a abrir', (
      tester,
    ) async {
      a.montaje.rota.fallaAlGuardar = true;
      await a.montar(tester);
      await a.hastaLaEntrevista(tester);

      await tester.binding.handlePopRoute();
      await a.asentar(tester);

      expect(a.montaje.agenda.recibidas, isEmpty);
      expect(a.montaje.almacen.guardadas, isEmpty);
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);
      expect(a.resultados, isEmpty, reason: '«¿Qué pasó?» sigue abierta para elegir de nuevo');
      expect(a.errorAlAbrir, isNull);
      expect(find.byKey(ClavesQuePaso.hoja), findsOneWidget);

      // Se arregló lo que fallaba: ahora «Empezar» anda.
      a.montaje.rota.fallaAlGuardar = false;
      await a.elegir(tester, OpcionQuePaso.entrevistaDada);
      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
      expect(a.montaje.almacen.guardadas, hasLength(1));
    });

    testWidgets(
      'si la visita no se guarda, el botón vuelve a estar habilitado y se puede reintentar',
      (tester) async {
        a.montaje.rota.fallaAlGuardar = true;
        a.montaje.agenda.falla = const FailureInesperado();
        a.montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 13, 30);
        await a.montar(tester);
        await a.hastaLaEntrevista(tester);

        await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

        expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
        expect(find.text(TextosEntrevista.noPudimosGuardar), findsOneWidget);
        expect(a.resultados, isEmpty);

        a.montaje.agenda.falla = null;
        await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

        expect(a.montaje.agenda.recibidas, hasLength(1));
        expect(a.resultados, [true]);
      },
    );
  });

  group('casos límite de «Entrevista dada»', () {
    testWidgets('doble tap en «Entrevista dada»: una sola entrevista y un solo gancho', (
      tester,
    ) async {
      await a.montar(tester);
      await a.abrirQuePaso(tester);

      final renglon = find.byKey(ClavesQuePaso.opcion(OpcionQuePaso.entrevistaDada));
      await tester.tap(renglon);
      await tester.tap(renglon, warnIfMissed: false);
      await a.asentar(tester);

      expect(a.entrevistas, hasLength(1));
      expect(a.montaje.almacen.guardadas, hasLength(1));
      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
    });

    testWidgets('doble tap en «No, guardar y volver al mapa»: una sola visita', (tester) async {
      await a.montar(tester);
      await a.hastaLaHoraDeSalida(tester);

      final boton = find.byKey(ClavesEntrevista.guardarYVolver);
      await tester.tap(boton);
      await tester.tap(boton, warnIfMissed: false);
      await a.asentar(tester);

      expect(a.montaje.agenda.recibidas, hasLength(1));
      expect(a.resultados, [true]);
    });

    testWidgets('volver atrás y reentrar: la misma entrevista, sin pisar la hora de inicio', (
      tester,
    ) async {
      await a.montar(tester);
      await a.hastaLaEntrevista(tester);
      final inicio = a.montaje.almacen.guardadas['col-1']!.inicio;
      await tester.binding.handlePopRoute();
      await a.asentar(tester);
      a.montaje.reloj = () => ahoraEntrevista.add(const Duration(minutes: 10));

      await a.hastaLaEntrevista(tester);

      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
      expect(a.montaje.almacen.guardadas, hasLength(1));
      expect(a.montaje.almacen.guardadas['col-1']!.inicio, inicio);
      expect(a.resultados, [true]);
    });

    testWidgets('con una entrevista en curso en otra casa se avisa y no se empieza otra', (
      tester,
    ) async {
      await a.montar(tester);
      await a
          .contenedor(tester)
          .read(entrevistaEnCursoProvider('col-1').notifier)
          .empezar(espacioId: 'esp-9', espacioPersonaId: 'ep-9');
      await a.asentar(tester);

      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.entrevistaDada);

      expect(find.byKey(ClavesQuePaso.falla), findsOneWidget);
      expect(
        find.textContaining('Ya tenés una entrevista en curso en Grecia 3307'),
        findsOneWidget,
      );
      expect(a.entrevistas, isEmpty);
      expect(a.montaje.almacen.guardadas['col-1']!.espacioId, 'esp-9');
      expect(a.resultados, isEmpty, reason: '«¿Qué pasó?» sigue abierta para elegir otra cosa');
    });

    testWidgets('con una entrevista en curso con otra persona de la MISMA casa no se descarta '
        '«¿Con quién?»: se avisa y la entrevista vieja queda como estaba', (tester) async {
      await a.montar(
        tester,
        personas: [
          clienteDePersonas('1', 'Pedro', apellido: 'Gómez'),
          clienteDePersonas('2', 'Ana', apellido: 'Pérez', minutos: 5),
        ],
      );
      await a
          .contenedor(tester)
          .read(entrevistaEnCursoProvider('col-1').notifier)
          .empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
      await a.asentar(tester);

      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.entrevistaDada);
      // «¿Con quién?»: se elige a Ana (ep-2).
      await tester.tap(find.text('Ana Pérez'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Empezar entrevista'));
      await a.asentar(tester);

      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsNothing);
      expect(find.textContaining('Ya tenés una entrevista en curso'), findsOneWidget);
      expect(a.montaje.almacen.guardadas['col-1']!.espacioPersonaId, 'ep-1');
      expect(a.salidasDeEntrevista, [false]);
      expect(a.resultados, isEmpty, reason: '«¿Qué pasó?» sigue abierta');
    });

    testWidgets('un nombre largo y textScaler 2.0 no rompen R·05 ni R·06', (tester) async {
      await a.montar(
        tester,
        escala: 2,
        personas: [
          clienteDePersonas(
            '1',
            'María de los Ángeles',
            apellido: 'Fernández de la Torre y Etcheverry',
          ),
        ],
      );
      a.montaje.rotulo = (
        direccion: 'Avenida Doctor Luis Alberto de Herrera 1234 · Depto 1203',
        persona: 'María de los Ángeles Fernández de la Torre y Etcheverry',
      );

      await a.hastaLaEntrevista(tester);
      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
      expect(tester.takeException(), isNull);

      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('«Vender» de «¿Qué pasó?» (decisión de Cristian, 04/11; no está en el canvas R·01)', () {
    testWidgets('se ofrece solo si la casa ya tuvo una entrevista dada', (tester) async {
      a.lector.porVinculo['ep-1'] = _ayer;
      await a.montar(tester);

      await a.abrirQuePaso(tester);

      expect(_vender, findsOneWidget);
      expect(find.text(TextosRegistrarVisita.vender), findsOneWidget);
      expect(find.text(TextosRegistrarVisita.ayudaVender('Pedro Gómez')), findsOneWidget);
    });

    testWidgets('sin entrevista previa en la casa no se dibuja', (tester) async {
      await a.montar(tester);

      await a.abrirQuePaso(tester);

      expect(_vender, findsNothing);
      expect(find.byKey(ClavesQuePaso.opcion(OpcionQuePaso.entrevistaDada)), findsOneWidget);
    });

    testWidgets('sin destino enchufado no se dibuja', (tester) async {
      a.lector.porVinculo['ep-1'] = _ayer;
      await a.montar(tester, conVender: false);

      await a.abrirQuePaso(tester);

      expect(_vender, findsNothing);
    });

    testWidgets('si no se puede leer cuándo fue la última entrevista, no se afirma: no se dibuja', (
      tester,
    ) async {
      a.lector.porVinculo['ep-1'] = _ayer;
      a.lector.falla = true;
      await a.montar(tester);

      await a.abrirQuePaso(tester);

      expect(_vender, findsNothing);
      expect(a.errorAlAbrir, isNull);
    });

    testWidgets('con dos personas vende a la de la entrevista más reciente', (tester) async {
      a.lector.porVinculo['ep-1'] = _ayer;
      a.lector.porVinculo['ep-2'] = _hoy;
      await a.montar(
        tester,
        personas: [
          clienteDePersonas('1', 'Pedro', apellido: 'Gómez'),
          clienteDePersonas('2', 'Ana', apellido: 'Pérez', minutos: 5),
        ],
      );

      await a.abrirQuePaso(tester);
      expect(find.text(TextosRegistrarVisita.ayudaVender('Ana Pérez')), findsOneWidget);
      await a.elegir(tester, OpcionQuePaso.vender);

      expect(a.ventas.single.espacioPersonaId, 'ep-2');
      expect(a.ventas.single.espacioId, 'esp-1');
      expect(find.text('Ana Pérez'), findsOneWidget);
    });

    testWidgets('abre la venta con la casa y la persona puestas, sin visita ni entrevista', (
      tester,
    ) async {
      a.lector.porVinculo['ep-1'] = _ayer;
      await a.montar(tester);
      await a.abrirQuePaso(tester);

      await a.elegir(tester, OpcionQuePaso.vender);

      expect(_ventaPagina, findsOneWidget);
      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
      expect(a.montaje.almacen.guardadas, isEmpty);
      expect(a.montaje.agenda.recibidas, isEmpty);
    });

    testWidgets(
      'la venta guardada llega a R·08 con la hoja de la casa abierta y sin visita atada',
      (tester) async {
        a.lector.porVinculo['ep-1'] = _ayer;
        await a.montar(tester);
        await a.abrirQuePaso(tester);
        await a.elegir(tester, OpcionQuePaso.vender);

        await a.armarLaVenta(tester);
        await a.registrarSinFecha(tester);

        final venta = a.entorno.ventas.recibidas.single.venta;
        expect(venta.visitaId, isNull, reason: 'no hay visita: es una venta suelta de la casa');
        expect(venta.espacioPersonaId, 'ep-1');
        expect(venta.numeroTalonario, '0039');
        expect(a.montaje.agenda.recibidas, isEmpty);
        expect(a.salidasDeVenta.single, isA<VentaRegistradaEnLaCasa>());
        expect(a.resultados, [false], reason: 'R·08: la hoja de la casa queda abierta');
        expect(find.text('Venta 0039 guardada.'), findsOneWidget);
      },
    );

    testWidgets('salir de la venta sin guardar avisa y «¿Qué pasó?» se vuelve a poder usar', (
      tester,
    ) async {
      a.lector.porVinculo['ep-1'] = _ayer;
      await a.montar(tester);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);

      await a.tocarKey(tester, const Key('venta_atras'));

      expect(a.entorno.ventas.recibidas, isEmpty);
      expect(a.resultados, isEmpty, reason: '«¿Qué pasó?» sigue abierta');
      expect(find.text(TextosEntrevista.ventaDeLaCasaNoGuardada), findsOneWidget);
      expect(_vender, findsOneWidget);
      // Ningún renglón quedó apagado ni con «Guardando…».
      expect(find.byKey(ClavesQuePaso.guardando), findsNothing);
    });

    testWidgets('si el guardado de la venta falla, nada queda trabado y se puede reintentar', (
      tester,
    ) async {
      a.lector.porVinculo['ep-1'] = _ayer;
      await a.montar(tester);
      a.entorno.ventas.respuesta = const FailureInesperado();
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
      await a.armarLaVenta(tester);

      await a.tocarKey(tester, const Key('venta_cta'));

      expect(_ventaPagina, findsOneWidget);
      expect(a.salidasDeVenta, isEmpty);

      a.entorno.ventas.respuesta = null;
      await a.registrarSinFecha(tester);

      expect(a.salidasDeVenta.single, isA<VentaRegistradaEnLaCasa>());
      expect(a.entorno.ventas.recibidas.length, greaterThanOrEqualTo(2));
    });

    testWidgets('dos ventas seguidas desde la casa: las dos se guardan, ninguna se pisa', (
      tester,
    ) async {
      a.lector.porVinculo['ep-1'] = _ayer;
      await a.montar(tester);

      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
      await a.armarLaVenta(tester, numero: '0039');
      await a.registrarSinFecha(tester);

      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
      await a.armarLaVenta(tester, numero: '0040');
      await a.registrarSinFecha(tester);

      expect(a.entorno.ventas.recibidas.map((r) => r.venta.numeroTalonario), ['0039', '0040']);
      expect(a.entorno.ventas.recibidas.map((r) => r.venta.id).toSet(), hasLength(2));
      expect(a.salidasDeVenta, hasLength(2));
    });

    testWidgets(
      '«Entrevista dada» y después «Vender» en la misma casa: dos acciones, una a continuación '
      'de la otra',
      (tester) async {
        a.lector.porVinculo['ep-1'] = _ayer;
        await a.montar(tester);
        await a.hastaLaHoraDeSalida(tester);
        await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

        await a.abrirQuePaso(tester);
        await a.elegir(tester, OpcionQuePaso.vender);
        await a.armarLaVenta(tester);
        await a.registrarSinFecha(tester);

        expect(
          a.montaje.agenda.recibidas.single.visita.tipoResultado,
          TipoResultadoVisita.entrevista,
        );
        expect(a.entorno.ventas.recibidas.single.venta.visitaId, isNull);
        expect(a.resultados, [true, false]);
      },
    );

    testWidgets('textScaler 2.0 y un nombre largo: «Vender» se lee y se toca sin desbordar', (
      tester,
    ) async {
      a.lector.porVinculo['ep-1'] = _ayer;
      await a.montar(
        tester,
        escala: 2,
        personas: [
          clienteDePersonas(
            '1',
            'María de los Ángeles',
            apellido: 'Fernández de la Torre y Etcheverry',
          ),
        ],
      );

      await a.abrirQuePaso(tester);

      expect(_vender, findsOneWidget);
      expect(tester.takeException(), isNull);
      await a.elegir(tester, OpcionQuePaso.vender);
      expect(_ventaPagina, findsOneWidget);
    });
  });
}

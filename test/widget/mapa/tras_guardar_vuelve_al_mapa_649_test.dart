// #649 (decisión de Cristian, 05/11, «Tras guardar»): después de guardar cualquier acción de la hoja
// de la casa —resultado de la visita, cobro, agenda— la hoja se cierra y queda el mapa libre, con la
// casa a la vista. Vale igual si la hoja se abrió en el mapa o en la Lista (la hoja modal).
import 'dart:async';

import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart'
    show ContextoDeCita, ContextoDeCobro, ContextoDeVisita;
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart' show asentarLista;
import 'navegacion_inicio_649_arnes.dart';

const _mapa = 1;
const _lista = 2;

final _vistaPrevia = find.byKey(ClavesMapaUbicaciones.vistaPrevia);
final _registrar = find.byKey(ClavesHojaCasa.registrarVisita);
final _cobrar = find.byKey(ClavesHojaCasa.cobrar);
final _agendar = find.byKey(ClavesHojaCasa.agendar);

/// La casa [id] elegida en el mapa, con su hoja a la vista.
Future<Montaje649> _conLaHojaEnElMapa(
  WidgetTester tester, {
  Destino649<ContextoDeVisita>? registrar,
  Destino649<ContextoDeCobro>? cobrar,
  Destino649<ContextoDeCita>? agendar,
  double escala = 1,
  String calle = 'Rivadavia',
}) async {
  final m = await montar649(
    tester,
    filas: [filaLista('a', calle: calle, numero: '100', metrosAlNorte: 30)],
    registrar: registrar,
    cobrar: cobrar,
    agendar: agendar,
    escala: escala,
  );
  await m.irA('mapa');
  m.mapa.tocarPunto('a');
  await m.asentar();
  expect(_vistaPrevia, findsOneWidget);
  return m;
}

/// La hoja modal de la casa abierta desde la Lista.
Future<Montaje649> _conLaHojaEnLaLista(
  WidgetTester tester, {
  Destino649<ContextoDeVisita>? registrar,
  Destino649<ContextoDeCobro>? cobrar,
  Destino649<ContextoDeCita>? agendar,
}) async {
  final m = await montar649(
    tester,
    filas: [filaLista('a', calle: 'Rivadavia', numero: '100')],
    registrar: registrar,
    cobrar: cobrar,
    agendar: agendar,
  );
  await m.irA('lista');
  await tester.tap(find.byKey(const ValueKey('a')));
  await asentarLista(tester);
  expect(_vistaPrevia, findsOneWidget, reason: 'la hoja modal de la casa');
  return m;
}

Future<void> _tocar(WidgetTester tester, Finder boton) async {
  await tester.ensureVisible(boton);
  await tester.tap(boton);
  await asentarLista(tester);
}

void main() {
  group('dado una casa elegida en el mapa, «Registrar visita»', () {
    testWidgets('cuando se guardó, entonces la hoja se cierra y el mapa queda libre', (
      tester,
    ) async {
      final m = await _conLaHojaEnElMapa(tester);

      await _tocar(tester, _registrar);

      expect(m.registrar.llamadas, hasLength(1));
      expect(m.registrar.llamadas.single.ubicacionId, 'a');
      expect(_vistaPrevia, findsNothing);
      expect(m.seleccionada, isNull);
      expect(m.pestana, _mapa);
      expect(m.navegacion.intencion, isNull);
    });

    testWidgets('cuando no se guardó nada (se cerró «¿Qué pasó?»), entonces la hoja sigue', (
      tester,
    ) async {
      final m = await _conLaHojaEnElMapa(tester, registrar: Destino649(false));

      await _tocar(tester, _registrar);

      expect(m.registrar.llamadas, hasLength(1));
      expect(_vistaPrevia, findsOneWidget);
      expect(m.seleccionada, 'a');
    });

    testWidgets(
      'cuando falla a mitad, entonces la hoja avisa, sigue abierta y el botón vuelve a andar',
      (tester) async {
        final destino = Destino649<ContextoDeVisita>()..falla = StateError('sin base');
        final m = await _conLaHojaEnElMapa(tester, registrar: destino);

        await _tocar(tester, _registrar);

        expect(find.textContaining('No pudimos abrir'), findsOneWidget);
        expect(m.seleccionada, 'a');
        expect(m.pestana, _mapa);

        destino
          ..falla = null
          ..resultado = true;
        await _tocar(tester, _registrar);

        expect(destino.llamadas, hasLength(2));
        expect(_vistaPrevia, findsNothing);
        expect(m.seleccionada, isNull);
      },
    );

    testWidgets('cuando se toca dos veces seguidas, entonces se abre una sola vez', (tester) async {
      final destino = Destino649<ContextoDeVisita>(true)..espera = Completer<void>();
      final m = await _conLaHojaEnElMapa(tester, registrar: destino);

      await tester.ensureVisible(_registrar);
      await tester.tap(_registrar);
      await tester.tap(_registrar, warnIfMissed: false);
      destino.espera!.complete();
      await asentarLista(tester);

      expect(destino.llamadas, hasLength(1));
      expect(m.seleccionada, isNull);
    });

    testWidgets(
      'cuando se toca «\$ Cobrar» mientras la otra acción no terminó, entonces la segunda no se '
      'abre y al terminar la primera la hoja se cierra',
      (tester) async {
        final destino = Destino649<ContextoDeVisita>(true)..espera = Completer<void>();
        final m = await _conLaHojaEnElMapa(tester, registrar: destino);

        await tester.ensureVisible(_registrar);
        await tester.tap(_registrar);
        await tester.pump();
        await tester.ensureVisible(_cobrar);
        await tester.tap(_cobrar, warnIfMissed: false);
        await tester.pump();
        destino.espera!.complete();
        await asentarLista(tester);

        expect(m.cobrar.llamadas, isEmpty);
        expect(destino.llamadas, hasLength(1));
        expect(m.seleccionada, isNull);
        expect(_vistaPrevia, findsNothing);
      },
    );

    testWidgets('cuando se vuelve a tocar la casa, entonces su hoja se abre de nuevo (reentrada)', (
      tester,
    ) async {
      final m = await _conLaHojaEnElMapa(tester);
      await _tocar(tester, _registrar);
      expect(_vistaPrevia, findsNothing);

      m.mapa.tocarPunto('a');
      await m.asentar();

      expect(_vistaPrevia, findsOneWidget);
      expect(m.seleccionada, 'a');
      expect(m.registrar.llamadas, hasLength(1), reason: 'abrir la hoja no registra nada solo');
    });

    testWidgets(
      'cuando el texto está al 200 % y la calle es larga, entonces se guarda y se cierra sin '
      'desbordar',
      (tester) async {
        final m = await _conLaHojaEnElMapa(
          tester,
          escala: 2,
          calle: 'Avenida Doctor Alejandro Gallinal',
        );

        await _tocar(tester, _registrar);

        expect(_vistaPrevia, findsNothing);
        expect(m.seleccionada, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('dado una casa elegida en el mapa, «\$ Cobrar»', () {
    testWidgets('cuando se cobró, entonces la hoja se cierra y el mapa queda libre', (
      tester,
    ) async {
      final m = await _conLaHojaEnElMapa(tester);

      await _tocar(tester, _cobrar);

      expect(m.cobrar.llamadas, hasLength(1));
      expect(_vistaPrevia, findsNothing);
      expect(m.seleccionada, isNull);
      expect(m.pestana, _mapa);
    });

    testWidgets('cuando no se cobró (se canceló), entonces la hoja sigue', (tester) async {
      final m = await _conLaHojaEnElMapa(tester, cobrar: Destino649(false));

      await _tocar(tester, _cobrar);

      expect(m.cobrar.llamadas, hasLength(1));
      expect(_vistaPrevia, findsOneWidget);
      expect(m.seleccionada, 'a');
    });

    testWidgets('cuando falla, entonces la hoja avisa y «\$ Cobrar» vuelve a poder tocarse', (
      tester,
    ) async {
      final destino = Destino649<ContextoDeCobro>()..falla = StateError('sin base');
      final m = await _conLaHojaEnElMapa(tester, cobrar: destino);

      await _tocar(tester, _cobrar);

      expect(find.textContaining('No pudimos abrir'), findsOneWidget);
      expect(m.seleccionada, 'a');

      destino
        ..falla = null
        ..resultado = true;
      await _tocar(tester, _cobrar);

      expect(destino.llamadas, hasLength(2));
      expect(m.seleccionada, isNull);
    });
  });

  group('dado una casa elegida en el mapa, «+ Agendar»', () {
    testWidgets('cuando se agendó, entonces la hoja se cierra y el mapa queda libre', (
      tester,
    ) async {
      final m = await _conLaHojaEnElMapa(tester);

      await _tocar(tester, _agendar);

      expect(m.agendar.llamadas, hasLength(1));
      expect(m.agendar.llamadas.single.ubicacionId, 'a');
      expect(_vistaPrevia, findsNothing);
      expect(m.seleccionada, isNull);
      expect(m.pestana, _mapa);
    });

    testWidgets('cuando no se agendó (se cerró «Agendar visita»), entonces la hoja sigue', (
      tester,
    ) async {
      final m = await _conLaHojaEnElMapa(tester, agendar: Destino649(false));

      await _tocar(tester, _agendar);

      expect(m.agendar.llamadas, hasLength(1));
      expect(_vistaPrevia, findsOneWidget);
      expect(m.seleccionada, 'a');
    });
  });

  group('dado la hoja de la casa abierta desde la Lista', () {
    testWidgets(
      'cuando se guardó el resultado, entonces la hoja se cierra y la colportora queda en el mapa '
      'libre',
      (tester) async {
        final m = await _conLaHojaEnLaLista(tester);
        expect(m.pestana, _lista);

        await _tocar(tester, _registrar);

        expect(m.registrar.llamadas, hasLength(1));
        expect(_vistaPrevia, findsNothing);
        expect(m.pestana, _mapa);
        expect(m.seleccionada, isNull);
        // El mapa nunca se había abierto: queda sobre la casa, no en todo el país.
        expect(m.mapa.armada, isTrue);
        expect(m.mapa.camara!.zoom, greaterThanOrEqualTo(MapaAlta.zoomCalle));
      },
    );

    testWidgets('cuando no se guardó nada, entonces la hoja sigue y se queda en la Lista', (
      tester,
    ) async {
      final m = await _conLaHojaEnLaLista(tester, registrar: Destino649(false));

      await _tocar(tester, _registrar);

      expect(_vistaPrevia, findsOneWidget);
      expect(m.pestana, _lista);
    });

    testWidgets('cuando se cobró, entonces la hoja se cierra y queda el mapa libre', (
      tester,
    ) async {
      final m = await _conLaHojaEnLaLista(tester);

      await _tocar(tester, _cobrar);

      expect(_vistaPrevia, findsNothing);
      expect(m.pestana, _mapa);
      expect(m.seleccionada, isNull);
    });

    testWidgets('cuando solo se cierra con la ✕, entonces la Lista queda donde estaba', (
      tester,
    ) async {
      final m = await _conLaHojaEnLaLista(tester);

      await _tocar(tester, find.byKey(ClavesMapaUbicaciones.cerrarVistaPrevia));

      expect(_vistaPrevia, findsNothing);
      expect(m.pestana, _lista);
      expect(m.registrar.llamadas, isEmpty);
    });
  });
}

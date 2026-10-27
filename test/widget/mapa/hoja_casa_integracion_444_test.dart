// Vista 39 (base), artboard C·01 y E·06 (HU-UBI-003, #444): la hoja de la casa dentro del mapa (vista 06)
// y de la Lista (vista 05), con los casos límite de cada flujo (doble toque, falla a mitad, volver atrás y
// reentrar, la hoja que sigue a los cambios, y «3 ubicaciones acá»).
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart' show puntoItalia;
import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_arnes.dart';

const _nbsp = ' ';

/// Las filas del canvas de la vista 06: «a» es «Av. Italia 1234», con cobranza pendiente, a 40 m.
List<UbicacionConResumen> _canvas() => [
  filaLista(
    'a',
    calle: 'Av. Italia',
    numero: '1234',
    metrosAlNorte: 40,
    espacios: 2,
    estado: EstadoCasa.cobranzaPendiente,
  ),
  filaLista('b', calle: 'Av. Italia', numero: '1250', metrosAlNorte: 55),
];

/// Tres ubicaciones en el mismo punto (varios números de una misma entrada): E·06.
List<UbicacionConResumen> _tresEnElMismoPunto() => [
  filaLista('u-1', calle: 'Grecia', numero: '3310', metrosAlNorte: 30),
  filaLista('u-2', calle: 'Grecia', numero: '3310 bis', metrosAlNorte: 30),
  filaLista('u-3', tipo: TipoUbicacion.negocio, calle: 'Grecia', numero: '3312', metrosAlNorte: 30),
];

Finder get _titulo => find.byKey(ClavesHojaCasa.titulo);
Finder get _registrar => find.byKey(ClavesHojaCasa.registrarVisita);
Finder get _elegir => find.byKey(ClavesEstadosHojaCasa.elegirUbicacion);

/// Mueve el mapa falso al zoom máximo, donde acercar más ya no separa las ubicaciones.
void _alZoomMaximo(MontajeMapaUbicaciones m) =>
    m.mapa.moverPorGesto(CamaraMapa(centro: puntoItalia, zoom: MapaAlta.zoomMaximo));

Future<void> _drenar(WidgetTester tester) => asentarLista(tester);

/// Toca [f] llevándolo antes a la vista: la hoja se desplaza y, a un tercio de la pantalla, el botón
/// de abajo queda bajo el pliegue.
Future<void> _tocarVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

void main() {
  group('C·01 en el mapa', () {
    testWidgets(
      'tocar un marcador abre la hoja de la casa con el resumen y sin la vista previa vieja',
      (tester) async {
        final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_canvas()));

        m.mapa.tocarPunto('a');
        await _drenar(tester);

        expect(find.byType(HojaCasa), findsOneWidget);
        expect(tester.widget<Text>(_titulo).data, 'Av. Italia 1234');
        expect(find.text('Pedro Gómez'), findsOneWidget);
        expect(find.text('Perro suelto: tocar timbre y esperar.'), findsOneWidget);
        expect(find.text('CASA · 2 ESPACIOS · A 40 M'), findsNothing);
      },
    );

    testWidgets('«Registrar visita» llega con la ubicación y el espacio de la casa tocada', (
      tester,
    ) async {
      final visitas = <ContextoDeVisita>[];
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(_canvas()),
        registrarVisita: visitas.add,
      );
      m.mapa.tocarPunto('b');
      await _drenar(tester);

      await _tocarVisible(tester, _registrar);
      await tester.pump();

      expect(visitas, [(ubicacionId: 'b', espacioId: 'esp-1', agendaId: null)]);
    });

    testWidgets('al volver de una vista hija, la hoja ya muestra el estado nuevo de la casa', (
      tester,
    ) async {
      final repo = RepoListaFalso(_canvas());
      final m = await montarMapaUbicaciones(tester, repo: repo);
      m.mapa.tocarPunto('a');
      await _drenar(tester);
      final antes = FormatoListaUbicaciones.estado(EstadoCasa.cobranzaPendiente);
      expect(find.textContaining(antes), findsOneWidget);

      repo.emitir([
        filaLista(
          'a',
          calle: 'Av. Italia',
          numero: '1234',
          metrosAlNorte: 40,
          espacios: 2,
          estado: EstadoCasa.ventaCompleta,
        ),
        ..._canvas().skip(1),
      ]);
      await _drenar(tester);

      expect(
        find.textContaining(FormatoListaUbicaciones.estado(EstadoCasa.ventaCompleta)),
        findsOneWidget,
      );
      expect(find.textContaining(antes), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la ✕ y el atrás del teléfono cierran la hoja y dejan la lista a la misma altura', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_canvas()));
      m.mapa.tocarPunto('a');
      await _drenar(tester);
      final alto = altoHoja(tester);

      await tester.tap(cerrarVistaPrevia);
      await _drenar(tester);
      expect(find.byType(HojaCasa), findsNothing);
      expect(fila('a'), findsOneWidget);
      expect(altoHoja(tester), alto);

      // Volver a entrar: otra hoja, sin lo que dejó la anterior.
      m.mapa.tocarPunto('b');
      await _drenar(tester);
      expect(tester.widget<Text>(_titulo).data, 'Av. Italia 1250');
      await tester.binding.handlePopRoute();
      await _drenar(tester);
      expect(find.byType(HojaCasa), findsNothing);
    });

    testWidgets('pasar de una casa a otra no arrastra el botón ocupado de la primera', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(_canvas()),
        registrarVisita: (_) => compuerta.future,
      );
      m.mapa.tocarPunto('a');
      await _drenar(tester);
      await _tocarVisible(tester, _registrar);
      await tester.pump();

      m.mapa.tocarPunto('b');
      await _drenar(tester);

      expect(tester.widget<FilledButton>(_registrar).onPressed, isNotNull);
      compuerta.complete();
      await tester.pump();
    });

    testWidgets(
      'E·02: si no se puede leer la casa, el aviso con «Reintentar» va dentro de la hoja',
      (tester) async {
        var intento = 0;
        final m = await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso(_canvas()),
          lecturaContexto: (_) => ++intento == 1
              ? Stream<ContextoDeLaCasa>.error(StateError('sin base'))
              : Stream.value(contextoDelCanvas),
        );
        m.mapa.tocarPunto('a');
        await _drenar(tester);

        expect(find.text('No pudimos leer esta casa en tu teléfono.'), findsOneWidget);
        expect(cerrarVistaPrevia, findsOneWidget, reason: 'la ✕ sigue ahí');

        await tester.tap(find.byKey(ClavesEstadosHojaCasa.accionDelAviso));
        await _drenar(tester);

        expect(find.text('Pedro Gómez'), findsOneWidget);
      },
    );

    testWidgets('E·05: lejos de la casa aparece el aviso con la distancia', (tester) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso([filaLista('l', calle: 'Lejos', numero: '1', metrosAlNorte: 650)]),
      );
      m.mapa.tocarPunto('l');
      await _drenar(tester);

      expect(find.textContaining('Estás a '), findsOneWidget);
      expect(find.byKey(ClavesEstadosHojaCasa.avisoLejos), findsOneWidget);
    });
  });

  group('E·06 · varias ubicaciones en el mismo punto', () {
    testWidgets('con el mapa en el zoom máximo, tocar el punto pide elegir: «3 ubicaciones acá» y '
        '«Elegí cuál», con la tocada primera', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_tresEnElMismoPunto()));
      _alZoomMaximo(m);

      m.mapa.tocarPunto('u-2');
      await _drenar(tester);

      expect(_elegir, findsOneWidget);
      expect(find.text('3 ubicaciones acá'), findsOneWidget);
      expect(find.text('Elegí cuál'), findsOneWidget);
      expect(find.byType(HojaCasa), findsNothing);
      expect(vistaPrevia, findsOneWidget);
      final primera = tester.getTopLeft(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-2'))).dy;
      expect(
        primera,
        lessThan(tester.getTopLeft(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1'))).dy),
      );
      expect(
        primera,
        lessThan(tester.getTopLeft(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-3'))).dy),
      );
    });

    testWidgets(
      'antes del zoom máximo no se pide elegir: se abre la más cercana y se acerca con los dedos',
      (tester) async {
        final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_tresEnElMismoPunto()));
        m.mapa.moverPorGesto(CamaraMapa(centro: puntoItalia, zoom: MapaAlta.zoomMaximo - 2));

        m.mapa.tocarPunto('u-2');
        await _drenar(tester);

        expect(_elegir, findsNothing);
        expect(tester.widget<Text>(_titulo).data, 'Grecia 3310 bis');
      },
    );

    testWidgets('una sola ubicación en el punto, aun con el zoom máximo, abre su hoja directo', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_canvas()));
      _alZoomMaximo(m);

      m.mapa.tocarPunto('a');
      await _drenar(tester);

      expect(_elegir, findsNothing);
      expect(find.byType(HojaCasa), findsOneWidget);
    });

    testWidgets('elegir una fila abre la hoja de esa ubicación y la ✕ vuelve a la lista', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_tresEnElMismoPunto()));
      _alZoomMaximo(m);
      m.mapa.tocarPunto('u-1');
      await _drenar(tester);

      await tester.tap(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-3')));
      await _drenar(tester);

      expect(_elegir, findsNothing);
      expect(tester.widget<Text>(_titulo).data, 'Grecia 3312');
      expect(seleccionadaId(tester), 'u-3');

      await tester.tap(cerrarVistaPrevia);
      await _drenar(tester);
      expect(find.byType(HojaCasa), findsNothing);
      expect(_elegir, findsNothing);
      expect(fila('u-1'), findsOneWidget);
    });

    testWidgets('la ✕ y el atrás cierran la elección sin abrir ninguna', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_tresEnElMismoPunto()));
      _alZoomMaximo(m);
      m.mapa.tocarPunto('u-1');
      await _drenar(tester);
      await tester.tap(cerrarVistaPrevia);
      await _drenar(tester);
      expect(_elegir, findsNothing);
      expect(seleccionadaId(tester), isNull);

      m.mapa.tocarPunto('u-1');
      await _drenar(tester);
      expect(_elegir, findsOneWidget);
      await tester.binding.handlePopRoute();
      await _drenar(tester);
      expect(_elegir, findsNothing);
      expect(find.byType(HojaCasa), findsNothing);
    });

    testWidgets('doble toque en una fila: se abre una sola hoja', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(_tresEnElMismoPunto()));
      _alZoomMaximo(m);
      m.mapa.tocarPunto('u-1');
      await _drenar(tester);

      final destino = find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-2'));
      await tester.tap(destino);
      await tester.tap(destino, warnIfMissed: false);
      await _drenar(tester);

      expect(find.byType(HojaCasa), findsOneWidget);
      expect(seleccionadaId(tester), 'u-2');
    });

    testWidgets('si una de las candidatas se da de baja mientras se elige, sale de la elección', (
      tester,
    ) async {
      final repo = RepoListaFalso(_tresEnElMismoPunto());
      final m = await montarMapaUbicaciones(tester, repo: repo);
      _alZoomMaximo(m);
      m.mapa.tocarPunto('u-1');
      await _drenar(tester);
      expect(find.text('3 ubicaciones acá'), findsOneWidget);

      repo.emitir(_tresEnElMismoPunto().take(2).toList());
      await _drenar(tester);

      expect(find.text('2 ubicaciones acá'), findsOneWidget);
      expect(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-3')), findsNothing);
    });

    testWidgets('a 200 % en 320 × 568 con 40 ubicaciones en el punto se recorre la lista', (
      tester,
    ) async {
      final muchas = [
        for (var i = 0; i < 40; i++)
          filaLista(
            'm-$i',
            calle: 'Calle larguísima de la ciudad',
            numero: '$i',
            metrosAlNorte: 30,
          ),
      ];
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(muchas),
        escala: 2,
        tamano: const Size(320, 568),
      );
      _alZoomMaximo(m);

      m.mapa.tocarPunto('m-0');
      await _drenar(tester);

      expect(find.text('40 ubicaciones acá'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(ClavesEstadosHojaCasa.filaDelPunto('m-39')),
        300,
        maxScrolls: 100,
        scrollable: find.descendant(of: _elegir, matching: find.byType(Scrollable)).first,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('C·01 en la Lista', () {
    UbicacionConResumen casa() => filaLista(
      'casa-1',
      calle: 'Rivadavia',
      numero: '100',
      estado: EstadoCasa.cobranzaPendiente,
    );

    testWidgets(
      'tocar una fila abre la hoja de la casa; la ✕ la cierra y la Lista queda como estaba',
      (tester) async {
        await montarLista(tester, repo: RepoListaFalso([casa()]));

        await tester.tap(find.text('Rivadavia 100'));
        await asentarLista(tester);

        expect(find.byType(HojaCasa), findsOneWidget);
        expect(tester.widget<Text>(_titulo).data, 'Rivadavia 100');
        expect(find.text('Pedro Gómez'), findsOneWidget);

        await tester.tap(cerrarVistaPrevia);
        await asentarLista(tester);

        expect(find.byType(HojaCasa), findsNothing);
        expect(find.text('Rivadavia 100'), findsOneWidget);
      },
    );

    testWidgets('doble toque en la fila: se abre una sola hoja', (tester) async {
      await montarLista(tester, repo: RepoListaFalso([casa()]));

      await tester.tap(find.text('Rivadavia 100'));
      await tester.tap(find.text('Rivadavia 100').first, warnIfMissed: false);
      await asentarLista(tester);

      expect(find.byType(HojaCasa), findsOneWidget);
    });

    testWidgets('el atrás cierra la hoja, y volver a tocar la misma fila abre otra entera', (
      tester,
    ) async {
      await montarLista(tester, repo: RepoListaFalso([casa()]));
      await tester.tap(find.text('Rivadavia 100'));
      await asentarLista(tester);

      await tester.binding.handlePopRoute();
      await asentarLista(tester);
      expect(find.byType(HojaCasa), findsNothing);

      await tester.tap(find.text('Rivadavia 100'));
      await asentarLista(tester);
      expect(find.byType(HojaCasa), findsOneWidget);
    });

    testWidgets('«Registrar visita» desde la Lista lleva la ubicación y el espacio', (
      tester,
    ) async {
      final visitas = <ContextoDeVisita>[];
      await montarLista(tester, repo: RepoListaFalso([casa()]), registrarVisita: visitas.add);
      await tester.tap(find.text('Rivadavia 100'));
      await asentarLista(tester);

      await _tocarVisible(tester, _registrar);
      await tester.pump();

      expect(visitas, [(ubicacionId: 'casa-1', espacioId: 'esp-1', agendaId: null)]);
    });

    testWidgets('si la casa cambia mientras la hoja está abierta, la hoja sigue a la Lista', (
      tester,
    ) async {
      final repo = RepoListaFalso([casa()]);
      await montarLista(tester, repo: repo);
      await tester.tap(find.text('Rivadavia 100'));
      await asentarLista(tester);
      expect(
        find.textContaining(FormatoListaUbicaciones.estado(EstadoCasa.cobranzaPendiente)),
        findsWidgets,
      );

      repo.emitir([
        filaLista('casa-1', calle: 'Rivadavia', numero: '100', estado: EstadoCasa.ventaCompleta),
      ]);
      await asentarLista(tester);

      final subtitulo = find.byKey(ClavesHojaCasa.subtitulo);
      expect(
        tester.widget<Text>(subtitulo).data,
        contains(FormatoListaUbicaciones.estado(EstadoCasa.ventaCompleta)),
      );
    });

    testWidgets('el destino propio (alAbrir) reemplaza a la hoja: no se abre nada encima', (
      tester,
    ) async {
      final abiertas = <String>[];
      await montarLista(
        tester,
        repo: RepoListaFalso([casa()]),
        alAbrir: (id, _) => abiertas.add(id),
      );

      await tester.tap(find.text('Rivadavia 100'));
      await asentarLista(tester);

      expect(abiertas, ['casa-1']);
      expect(find.byType(HojaCasa), findsNothing);
    });

    testWidgets(
      'si la casa sale de la lista que se ve (se dio de baja) mientras la hoja está abierta, '
      'la hoja queda con lo último que tuvo y se puede cerrar',
      (tester) async {
        final repo = RepoListaFalso([casa()]);
        await montarLista(tester, repo: repo);
        await tester.tap(find.text('Rivadavia 100'));
        await asentarLista(tester);

        repo.emitir(const []);
        await asentarLista(tester);

        expect(find.byType(HojaCasa), findsOneWidget);
        expect(tester.widget<Text>(_titulo).data, 'Rivadavia 100');
        expect(tester.takeException(), isNull);

        await tester.tap(cerrarVistaPrevia);
        await asentarLista(tester);
        expect(find.byType(HojaCasa), findsNothing);
      },
    );
  });

  test('el texto de lejos usa el espacio duro de las distancias', () {
    expect(TextosEstadosHojaCasa.lejos(650), 'Estás a 650${_nbsp}m de esta casa.');
  });
}

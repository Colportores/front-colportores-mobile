// #649: el shell de Inicio guarda la pestaña y atiende «ir a la casa» (llevarla al mapa principal,
// centrarla, elegirla y subir su hoja) y «volver al mapa tras guardar» (hoja cerrada, casa a la vista).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/inicio/presentation/providers/navegacion_inicio_provider.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import 'lista_ubicaciones_arnes.dart' show asentarLista;
import 'navegacion_inicio_649_arnes.dart';

const _mapa = 1;
const _hoy = 0;

/// La hoja de la casa a un tercio (C·01, el resumen): está la vista previa y no las pestañas de C·02.
final _resumen = find.byKey(ClavesMapaUbicaciones.vistaPrevia);
final _hojaArriba = find.byKey(ClavesHojaCasa.pestanas);

void main() {
  group('dado el shell armado, «ir a la casa» desde cada pestaña', () {
    for (final desde in ['hoy', 'lista', 'agenda', 'ventas', 'cuenta']) {
      testWidgets(
        'cuando se pide desde «$desde», entonces queda «Mapa» con la casa elegida y su hoja a un '
        'tercio',
        (tester) async {
          final m = await montar649(
            tester,
            filas: [filaLista('a'), filaLista('b', metrosAlNorte: 40)],
          );
          await m.irA(desde);

          m.notificador.irALaCasa('b');
          await m.asentar();

          expect(m.pestana, _mapa);
          expect(m.seleccionada, 'b');
          expect(_resumen, findsOneWidget);
          expect(_hojaArriba, findsNothing, reason: 'sube el resumen (C·01), no la hoja arriba');
          expect(m.navegacion.intencion, isNull, reason: 'el mapa la atendió');
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'cuando el mapa nunca se abrió, entonces la intención espera a que se arme y se aplica sola',
      (tester) async {
        final m = await montar649(
          tester,
          filas: [filaLista('a'), filaLista('b', metrosAlNorte: 40)],
        );
        expect(m.mapa.armada, isFalse);
        expect(m.pestana, _hoy);

        m.notificador.irALaCasa('b');
        await m.asentar();

        expect(m.mapa.armada, isTrue);
        expect(m.seleccionada, 'b');
        expect(_resumen, findsOneWidget);
      },
    );

    testWidgets(
      'cuando la casa está lejos del GPS, entonces la cámara va a la casa y el GPS que llega '
      'después no se la saca',
      (tester) async {
        final casa = filaLista('lejos', metrosAlNorte: 4000);
        final m = await montar649(
          tester,
          filas: [filaLista('cerca'), casa],
          gps: GpsFalso(Right(lecturaGps(8))),
        );

        m.notificador.irALaCasa('lejos');
        await m.asentar();
        await m.asentar();

        final camara = m.mapa.camara!;
        final aLaCasa = ProyeccionMercator.distanciaPixeles(
          camara.centro,
          casa.ubicacion.coordenadas,
          camara.zoom,
        );
        final alGps = ProyeccionMercator.distanciaPixeles(camara.centro, puntoItalia, camara.zoom);
        expect(aLaCasa, lessThan(alGps), reason: 'la cámara quedó sobre la casa, no sobre el GPS');
        expect(aLaCasa, lessThan(400));
      },
    );

    testWidgets(
      'cuando el mapa ya estaba abierto y se movió a mano, entonces «ir a la casa» igual la centra',
      (tester) async {
        final casa = filaLista('lejos', metrosAlNorte: 4000);
        final m = await montar649(tester, filas: [filaLista('cerca'), casa]);
        await m.irA('mapa');
        m.mapa.moverPorGesto(const CamaraMapa(centro: puntoItalia, zoom: 12));
        await m.asentar();
        await m.irA('agenda');

        m.notificador.irALaCasa('lejos');
        await m.asentar();

        final camara = m.mapa.camara!;
        expect(
          ProyeccionMercator.distanciaPixeles(
            camara.centro,
            casa.ubicacion.coordenadas,
            camara.zoom,
          ),
          lessThan(400),
        );
        expect(m.seleccionada, 'lejos');
      },
    );

    testWidgets(
      'cuando se pide la casa que ya estaba elegida, entonces sigue elegida (reentrada)',
      (tester) async {
        final m = await montar649(
          tester,
          filas: [filaLista('a'), filaLista('b', metrosAlNorte: 40)],
        );
        m.notificador.irALaCasa('b');
        await m.asentar();
        await m.irA('lista');

        m.notificador.irALaCasa('b');
        await m.asentar();

        expect(m.pestana, _mapa);
        expect(m.seleccionada, 'b');
        expect(_resumen, findsOneWidget);
      },
    );

    testWidgets(
      'cuando la casa no es de la colportora, entonces el mapa queda en su pestaña sin elegir nada '
      'ni colgar la intención',
      (tester) async {
        final m = await montar649(tester, filas: [filaLista('a')]);

        m.notificador.irALaCasa('de-otro');
        await m.asentar();

        expect(m.pestana, _mapa);
        expect(m.seleccionada, isNull);
        expect(_resumen, findsNothing);
        expect(m.navegacion.intencion, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cuando se piden dos casas seguidas antes de que el mapa responda, entonces queda la última, '
      'con una sola hoja',
      (tester) async {
        final m = await montar649(
          tester,
          filas: [filaLista('a'), filaLista('b', metrosAlNorte: 40)],
        );

        m.notificador.irALaCasa('a');
        m.notificador.irALaCasa('b');
        await m.asentar();

        expect(m.seleccionada, 'b');
        expect(_resumen, findsOneWidget);
      },
    );

    testWidgets('cuando la lista no se puede leer, entonces la intención no queda colgada', (
      tester,
    ) async {
      final m = await montar649(tester, filas: [filaLista('a')], listaSePuedeLeer: false);

      m.notificador.irALaCasa('a');
      await m.asentar();

      expect(m.navegacion.intencion, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'cuando el texto está al 200 %, entonces la casa se elige y la hoja sube sin desbordar',
      (tester) async {
        final m = await montar649(
          tester,
          filas: [filaLista('a', calle: 'Avenida Doctor Alejandro Gallinal', numero: '1234')],
          escala: 2,
        );
        await m.irA('lista');

        m.notificador.irALaCasa('a');
        await m.asentar();

        expect(m.pestana, _mapa);
        expect(m.seleccionada, 'a');
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('dado el shell armado, «volver al mapa» tras guardar', () {
    testWidgets(
      'cuando la hoja de la casa estaba abierta, entonces se cierra y el mapa queda libre en la '
      'misma pestaña',
      (tester) async {
        final m = await montar649(tester, filas: [filaLista('a', metrosAlNorte: 30)]);
        await m.irA('mapa');
        m.mapa.tocarPunto('a');
        await m.asentar();
        expect(_resumen, findsOneWidget);

        m.notificador.volverAlMapa('a');
        await m.asentar();

        expect(m.pestana, _mapa);
        expect(m.seleccionada, isNull);
        expect(_resumen, findsNothing);
        expect(m.navegacion.intencion, isNull);
      },
    );

    testWidgets('cuando viene de otra pestaña, entonces la pestaña Mapa queda activa y libre', (
      tester,
    ) async {
      final m = await montar649(tester, filas: [filaLista('a', metrosAlNorte: 30)]);
      await m.irA('agenda');

      m.notificador.volverAlMapa('a');
      await m.asentar();

      expect(m.pestana, _mapa);
      expect(m.seleccionada, isNull);
      expect(_resumen, findsNothing);
    });

    testWidgets('cuando la casa ya se ve en el mapa, entonces la cámara no se mueve', (
      tester,
    ) async {
      final m = await montar649(tester, filas: [filaLista('a', metrosAlNorte: 30)]);
      await m.irA('mapa');
      m.mapa.tocarPunto('a');
      await m.asentar();
      final movimientos = m.mapa.movimientos.length;

      m.notificador.volverAlMapa('a');
      await m.asentar();

      expect(m.mapa.movimientos.length, movimientos);
    });

    testWidgets(
      'cuando la casa quedó fuera de la vista, entonces la cámara la trae sin subir su hoja',
      (tester) async {
        final casa = filaLista('lejos', metrosAlNorte: 4000);
        final m = await montar649(tester, filas: [filaLista('cerca'), casa]);
        await m.irA('mapa');
        m.mapa.tocarPunto('lejos');
        await m.asentar();
        m.mapa.moverPorGesto(const CamaraMapa(centro: puntoItalia, zoom: 12));
        await m.asentar();

        m.notificador.volverAlMapa('lejos');
        await m.asentar();

        final camara = m.mapa.camara!;
        expect(
          ProyeccionMercator.distanciaPixeles(
            camara.centro,
            casa.ubicacion.coordenadas,
            camara.zoom,
          ),
          lessThan(400),
        );
        expect(m.seleccionada, isNull);
        expect(_resumen, findsNothing);
      },
    );

    testWidgets('cuando se vuelve a tocar la casa, entonces su hoja se abre de nuevo (reentrada)', (
      tester,
    ) async {
      final m = await montar649(tester, filas: [filaLista('a', metrosAlNorte: 30)]);
      await m.irA('mapa');
      m.mapa.tocarPunto('a');
      await m.asentar();
      m.notificador.volverAlMapa('a');
      await m.asentar();

      m.mapa.tocarPunto('a');
      await m.asentar();

      expect(m.seleccionada, 'a');
      expect(_resumen, findsOneWidget);
    });

    testWidgets('cuando llegan «ir a la casa» y «tras guardar» seguidas, entonces gana la última', (
      tester,
    ) async {
      final m = await montar649(tester, filas: [filaLista('a', metrosAlNorte: 30)]);

      m.notificador.irALaCasa('a');
      m.notificador.volverAlMapa('a');
      await m.asentar();

      expect(m.pestana, _mapa);
      expect(m.seleccionada, isNull);
      expect(_resumen, findsNothing);
    });
  });

  group('dado el shell armado, el atrás del sistema', () {
    testWidgets(
      'cuando se llegó a la casa desde la Agenda, entonces cierra la hoja y vuelve a «Hoy»: no '
      'cierra la app',
      (tester) async {
        final m = await montar649(tester, filas: [filaLista('a', metrosAlNorte: 30)]);
        await m.irA('agenda');
        m.notificador.irALaCasa('a');
        await m.asentar();
        expect(_resumen, findsOneWidget);

        await tester.binding.handlePopRoute();
        await m.asentar();
        expect(_resumen, findsNothing, reason: 'primero se cierra la hoja de la casa');
        expect(m.pestana, _mapa);

        await tester.binding.handlePopRoute();
        await m.asentar();
        expect(m.pestana, _hoy, reason: 'desde otra pestaña el atrás vuelve a «Hoy»');
      },
    );
  });

  group('dado un shell nuevo', () {
    testWidgets(
      'cuando el provider quedó en otra pestaña de una sesión anterior, entonces la pantalla '
      'principal arranca en «Hoy»',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final contenedor = ProviderContainer(
          overrides: [
            jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
            ...overridesLista(repo: RepoListaFalso([filaLista('a')])),
            ...overridesPestanaMapa(),
          ],
        );
        addTearDown(contenedor.dispose);
        contenedor.read(navegacionInicioProvider.notifier).ir(PestanaInicio.agenda);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: contenedor,
            child: MaterialApp(
              theme: temaClaro(),
              home: InicioPage(sesion: sesion649),
            ),
          ),
        );
        await asentarLista(tester);

        expect(contenedor.read(navegacionInicioProvider).actual, PestanaInicio.hoy);
        expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, _hoy);
      },
    );
  });
}

// HU-UBI-003 · vista 06 «Mapa de ubicaciones», seguimiento de la ubicación (#670, decisión de
// Cristian del 05/11, «GPS viejo»): el botón de ubicación tiene tres modos —libre, seguir y seguir y
// girar— y el mapa sigue a la colportora como Maps. El canvas solo dibuja «Mi ubicación» (06C·01):
// los tres modos no tienen artboard, así que acá se prueba cada modo, sus cambios y sus casos límite.
import 'dart:math' as math;

import 'package:colportores_mobile/core/error/failure.dart' show MotivoSinGps;
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/modo_seguimiento.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas, gpsSinPermiso;

const _adelante = Coordenadas(lat: -34.88700, lon: -56.13024);
const _masAdelante = Coordenadas(lat: -34.88650, lon: -56.13000);

LecturaGps _lectura(Coordenadas punto, {double? rumbo}) =>
    LecturaGps(coordenadas: punto, precisionMetros: 5, rumboGrados: rumbo);

ModoSeguimiento _modo(WidgetTester tester) =>
    contenedorDeLaPestana(tester).read(ubicacionColportorProvider).modo;

String _etiqueta(WidgetTester tester) =>
    tester.getSemantics(botonMiUbicacion).getSemanticsData().label;

Finder _icono(IconData icono) =>
    find.descendant(of: botonMiUbicacion, matching: find.byIcon(icono));

/// A cuántos dp del centro de la cámara cae [punto], gire como gire el mapa.
double _pixelesAlPunto(FabricaMapaFalsa mapa, Coordenadas punto) {
  final camara = mapa.camara!;
  final centro = ProyeccionMercator.aPixeles(camara.centro, camara.zoom);
  final buscado = ProyeccionMercator.aPixeles(punto, camara.zoom);
  return math.sqrt(math.pow(centro.x - buscado.x, 2) + math.pow(centro.y - buscado.y, 2));
}

/// Toca el botón de ubicación y deja pasar lo que dispara.
Future<void> _tocarBoton(WidgetTester tester) async {
  await tester.tap(botonMiUbicacion);
  await asentarLista(tester);
}

/// El teléfono se movió: llega una lectura por el stream del seguimiento.
Future<void> _moverse(WidgetTester tester, GpsFalso gps, LecturaGps lectura) async {
  gps.moverse(lectura);
  await asentarLista(tester);
}

void main() {
  group('el botón de ubicación y sus tres modos', () {
    testWidgets('arranca en «Mapa libre» y cada toque pasa al modo siguiente, con su ícono y su '
        'etiqueta', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      expect(_etiqueta(tester), 'Mapa libre');
      expect(_icono(Icons.location_searching), findsOneWidget);

      await _tocarBoton(tester);
      expect(_etiqueta(tester), 'Seguir mi ubicación');
      expect(_icono(Icons.my_location), findsOneWidget);

      await _tocarBoton(tester);
      expect(_etiqueta(tester), 'Seguir y girar con el teléfono');
      expect(_icono(Icons.navigation), findsOneWidget);

      await _tocarBoton(tester);
      expect(_etiqueta(tester), 'Mapa libre');
      expect(_icono(Icons.location_searching), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('el modo no cambia de nombre sin que el botón se toque ni deja pista que se '
        'repita', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);

      final nodo = tester.getSemantics(botonMiUbicacion).getSemanticsData();
      expect(nodo.hint, isEmpty);
      expect(nodo.hasAction(SemanticsAction.tap), isTrue);
      semantica.dispose();
    });

    testWidgets('sin GPS el botón sigue apagado: no hay a quién seguir y no cambia de modo', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(canvas()),
        gps: gpsSinPermiso(),
      );

      await tester.tap(botonMiUbicacion, warnIfMissed: false);
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.libre);
      expect(m.gps.seguimientosAbiertos, 0);
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets('en cada modo el botón mide al menos 48 x 48 con el texto a $escala', (
        tester,
      ) async {
        await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso(canvas()),
          tamano: const Size(360, 640),
          escala: escala,
        );

        for (var i = 0; i < ModoSeguimiento.values.length; i++) {
          final tam = tester.getSize(botonMiUbicacion);
          expect(tam.width, greaterThanOrEqualTo(48), reason: 'modo ${_modo(tester)}');
          expect(tam.height, greaterThanOrEqualTo(48), reason: 'modo ${_modo(tester)}');
          await _tocarBoton(tester);
        }
        expect(_modo(tester), ModoSeguimiento.libre);
      });
    }
  });

  group('seguir', () {
    testWidgets('el mapa va a la posición, abre el stream y la sigue cuando la colportora camina', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      m.mapa.moverPorGesto(
        m.mapa.camara!.conCentro(const Coordenadas(lat: -34.5, lon: -56.0)).conZoom(12),
      );
      await tester.pump();
      expect(m.gps.siguiendo, isFalse, reason: 'libre: sin stream');

      await _tocarBoton(tester);

      expect(m.gps.siguiendo, isTrue);
      expect(dpALaDerechaDelPunto(m.mapa, puntoItalia), closeTo(0, 0.01));
      expect(dpBajoElPunto(m.mapa, puntoItalia), closeTo(altoHoja(tester) / 2, 0.01));
      expect(m.mapa.camara!.zoom, MapaAlta.zoomCalle, reason: 'al entrar se acerca a la calle');

      await _moverse(tester, m.gps, _lectura(_adelante));
      expect(dpALaDerechaDelPunto(m.mapa, _adelante), closeTo(0, 0.01));
      expect(dpBajoElPunto(m.mapa, _adelante), closeTo(altoHoja(tester) / 2, 0.01));

      await _moverse(tester, m.gps, _lectura(_masAdelante));
      expect(dpBajoElPunto(m.mapa, _masAdelante), closeTo(altoHoja(tester) / 2, 0.01));
      expect(_modo(tester), ModoSeguimiento.seguir, reason: 'seguir no se cancela solo');
      expect(m.mapa.camara!.rumbo, 0, reason: 'seguir no gira el mapa');
    });

    testWidgets('lo que la cámara se mueve sola no se toma por un dedo: sigue en «seguir» tras '
        'muchas lecturas seguidas', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);

      for (var i = 0; i < 8; i++) {
        gpsPaso(m.gps, i);
        await tester.pump(const Duration(milliseconds: 10));
      }
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.seguir);
    });

    testWidgets('el pellizco de zoom no suelta a la colportora', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      final antes = m.mapa.camara!;

      final centro = tester.getCenter(find.byKey(const Key('pestana_mapa')));
      final a = await tester.startGesture(centro - const Offset(40, 0), pointer: 1);
      final b = await tester.startGesture(centro + const Offset(40, 0), pointer: 2);
      for (var i = 0; i < 6; i++) {
        await a.moveBy(const Offset(-6, 0));
        await b.moveBy(const Offset(14, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await asentarLista(tester, 10);

      expect(m.mapa.camara!.zoom, greaterThan(antes.zoom), reason: 'el pellizco hizo zoom');
      expect(_modo(tester), ModoSeguimiento.seguir);
    });
  });

  group('seguir y girar', () {
    testWidgets('el mapa gira hacia donde mira la colportora y la lectura sin rumbo lo deja como '
        'estaba', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      expect(_modo(tester), ModoSeguimiento.seguirYGirar);
      expect(m.mapa.camara!.rumbo, 0, reason: 'quieta no hay rumbo: no gira a cualquier lado');

      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 90));
      expect(m.mapa.camara!.rumbo, 90);
      // El punto sigue en el medio de lo que la hoja deja libre, con el mapa girado.
      expect(_pixelesAlPunto(m.mapa, _adelante), closeTo(altoHoja(tester) / 2, 0.01));
      expect(m.mapa.camara!.centro, isNot(_adelante));

      await _moverse(tester, m.gps, _lectura(_masAdelante, rumbo: 200));
      expect(m.mapa.camara!.rumbo, 200);

      await _moverse(tester, m.gps, _lectura(_adelante));
      expect(m.mapa.camara!.rumbo, 200, reason: 'sin rumbo conserva el último');
      expect(_modo(tester), ModoSeguimiento.seguirYGirar);
    });

    testWidgets('al volver a «Mapa libre» con el botón, el norte vuelve arriba y el stream se '
        'cierra', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 135));
      expect(m.mapa.camara!.rumbo, 135);

      await _tocarBoton(tester);

      expect(_modo(tester), ModoSeguimiento.libre);
      expect(m.mapa.camara!.rumbo, 0);
      expect(m.gps.siguiendo, isFalse);
    });

    testWidgets('al volver a «seguir» después de girar, el norte queda arriba y la lectura con '
        'rumbo no lo gira', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 135));

      // Ciclo entero y otra vez a «seguir»: el mapa vuelve al norte.
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      expect(_modo(tester), ModoSeguimiento.seguir);
      await _moverse(tester, m.gps, _lectura(_masAdelante, rumbo: 45));

      expect(m.mapa.camara!.rumbo, 0);
    });
  });

  group('la colportora toma el mapa con el dedo', () {
    testWidgets('arrastrar el mapa mientras la sigue lo pasa a «Mapa libre» y cierra el stream', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      expect(m.gps.siguiendo, isTrue);

      m.mapa.moverPorGesto(m.mapa.camara!.conCentro(const Coordenadas(lat: -34.90, lon: -56.15)));
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.libre);
      expect(m.gps.siguiendo, isFalse);
      expect(_etiqueta(tester), 'Mapa libre');
      semantica.dispose();
    });

    testWidgets('si el mapa estaba girado y ella lo mueve, se queda como lo dejó (no se endereza '
        'de golpe bajo su dedo)', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 135));
      final movimientos = m.mapa.movimientos.length;

      m.mapa.moverPorGesto(m.mapa.camara!.conCentro(const Coordenadas(lat: -34.90, lon: -56.15)));
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.libre);
      expect(m.mapa.camara!.rumbo, 135);
      expect(m.mapa.movimientos.length, movimientos, reason: 'no hay otro movimiento del código');
    });

    testWidgets('después de soltarla, un toque al botón la vuelve a seguir desde el principio', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      m.mapa.moverPorGesto(m.mapa.camara!.conCentro(const Coordenadas(lat: -34.90, lon: -56.15)));
      await asentarLista(tester);

      await _tocarBoton(tester);

      expect(_modo(tester), ModoSeguimiento.seguir);
      expect(dpALaDerechaDelPunto(m.mapa, puntoItalia), closeTo(0, 0.01));
    });
  });

  group('batería: el stream solo vive con el mapa a la vista', () {
    testWidgets('cambiar de pestaña lo cierra, se recuerda el modo y al volver sigue donde '
        'está', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      await _tocarBoton(tester);
      expect(m.gps.siguiendo, isTrue);

      m.activa.value = false;
      await asentarLista(tester);
      expect(m.gps.siguiendo, isFalse, reason: 'otra pestaña: sin stream');
      expect(_modo(tester), ModoSeguimiento.seguirYGirar, reason: 'el modo se recuerda');

      // Mientras tanto la colportora caminó: al volver, la primera lectura la lleva a ella.
      m.activa.value = true;
      await asentarLista(tester);
      expect(m.gps.siguiendo, isTrue);
      expect(_modo(tester), ModoSeguimiento.seguirYGirar);
      await _moverse(tester, m.gps, _lectura(_masAdelante, rumbo: 10));
      expect(m.mapa.camara!.rumbo, 10);
      expect(_pixelesAlPunto(m.mapa, _masAdelante), closeTo(altoHoja(tester) / 2, 0.01));
    });

    testWidgets('con la app en segundo plano se cierra y al volver se reabre', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      expect(m.gps.siguiendo, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await asentarLista(tester);
      expect(m.gps.siguiendo, isFalse, reason: 'sin pantalla no se gasta batería');
      expect(_modo(tester), ModoSeguimiento.seguir);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await asentarLista(tester);
      expect(m.gps.siguiendo, isTrue);
    });

    testWidgets('ir y volver varias veces a la pestaña no deja streams colgados', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);

      for (var i = 0; i < 4; i++) {
        m.activa.value = false;
        await asentarLista(tester, 3);
        m.activa.value = true;
        await asentarLista(tester, 3);
      }

      expect(m.gps.siguiendo, isTrue);
      expect(m.gps.seguimientosAbiertos - m.gps.seguimientosCerrados, 1);
    });

    testWidgets('cerrar la pantalla con el seguimiento prendido cierra el stream y no deja '
        'errores', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      expect(m.gps.siguiendo, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));

      expect(m.gps.siguiendo, isFalse);
    });
  });

  group('casos límite', () {
    testWidgets('dos toques seguidos al botón dejan «seguir y girar» y un solo stream', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      await tester.tap(botonMiUbicacion);
      await tester.tap(botonMiUbicacion);
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.seguirYGirar);
      expect(m.gps.seguimientosAbiertos - m.gps.seguimientosCerrados, 1);
    });

    testWidgets('tres toques seguidos dan la vuelta completa: «Mapa libre» y sin stream', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));

      for (var i = 0; i < 3; i++) {
        await tester.tap(botonMiUbicacion);
      }
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.libre);
      expect(m.gps.siguiendo, isFalse);
      expect(m.mapa.camara!.rumbo, 0);
    });

    for (final motivo in [MotivoSinGps.permisoDenegado, MotivoSinGps.servicioApagado]) {
      testWidgets('si el seguimiento se corta a mitad ($motivo): vuelve a «Mapa libre», lo dice y '
          'el botón no queda trabado', (tester) async {
        final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
        await _tocarBoton(tester);
        await _tocarBoton(tester);
        await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 90));

        m.gps.fallarElSeguimiento(motivo);
        await asentarLista(tester);

        expect(_modo(tester), ModoSeguimiento.libre);
        expect(m.gps.siguiendo, isFalse);
        expect(find.text(TextosMapaUbicaciones.seguimientoCortado), findsOneWidget);
        expect(find.text(TextosMapaUbicaciones.activarGps), findsWidgets);
        expect(m.mapa.camara!.rumbo, 0, reason: 'el norte vuelve arriba');

        // «Activar GPS» desde el aviso funciona y no se rompe nada.
        await tester.tap(find.widgetWithText(SnackBarAction, TextosMapaUbicaciones.activarGps));
        await asentarLista(tester);
        expect(m.gps.activaciones, [motivo]);
      });
    }

    testWidgets('si el stream falla por una señal que se pierde, se corta pero el botón sigue '
        'andando y se puede volver a seguir', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);

      m.gps.fallarElSeguimiento(MotivoSinGps.sinSenal);
      await asentarLista(tester);
      expect(_modo(tester), ModoSeguimiento.libre);
      expect(find.text(TextosMapaUbicaciones.seguimientoCortado), findsOneWidget);

      await _tocarBoton(tester);
      expect(_modo(tester), ModoSeguimiento.seguir);
      expect(m.gps.siguiendo, isTrue);
      await _moverse(tester, m.gps, _lectura(_adelante));
      expect(dpBajoElPunto(m.mapa, _adelante), closeTo(altoHoja(tester) / 2, 0.01));
    });

    testWidgets('el aviso de corte no se amontona: dos cortes seguidos dejan un solo aviso', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      m.gps.fallarElSeguimiento(MotivoSinGps.sinSenal);
      await asentarLista(tester);
      await _tocarBoton(tester);
      m.gps.fallarElSeguimiento(MotivoSinGps.sinSenal);
      await asentarLista(tester);

      expect(find.text(TextosMapaUbicaciones.seguimientoCortado), findsOneWidget);
    });

    testWidgets('con muchas ubicaciones en el mapa y el texto a 2.0 el seguimiento sigue '
        'centrando a la colportora', (tester) async {
      final repo = RepoListaFalso([
        for (var i = 0; i < 60; i++)
          filaLista(
            'u$i',
            calle: 'Una calle con un nombre larguísimo número $i',
            numero: '${1000 + i}',
            metrosAlNorte: 20.0 + i * 7,
          ),
      ]);
      final m = await montarMapaUbicaciones(tester, repo: repo, escala: 2);

      await _tocarBoton(tester);
      await _moverse(tester, m.gps, _lectura(_adelante, rumbo: 45));

      expect(_modo(tester), ModoSeguimiento.seguir);
      expect(dpBajoElPunto(m.mapa, _adelante), closeTo(altoHoja(tester) / 2, 0.01));
    });
  });

  group('el alta desde el mapa', () {
    testWidgets('el toque largo mientras la sigue abre el alta en ese punto sin soltar el '
        'seguimiento', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      const punto = Coordenadas(lat: -34.8880, lon: -56.1310);

      m.mapa.tocarLargo(punto);
      await asentarLista(tester);

      expect(m.altas, [punto]);
      expect(_modo(tester), ModoSeguimiento.seguir);
    });
  });
}

/// Una lectura nueva del stream, un poco más al norte cada vez.
void gpsPaso(GpsFalso gps, int i) => gps.moverse(
  LecturaGps(
    coordenadas: Coordenadas(lat: -34.8870 + i * 0.00002, lon: -56.13024),
    precisionMetros: 5,
  ),
);

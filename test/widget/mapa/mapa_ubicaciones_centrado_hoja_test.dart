// HU-UBI-003 · vista 06 (#199, hallazgo M1 del #294): el punto azul («Tu ubicación») nunca queda
// debajo de la hoja. El encuadre al GPS, «Mi ubicación» y la subida sola de la hoja (sin
// ubicaciones o con error de lectura) centran el GPS en la parte que la hoja deja libre, no en el
// centro de todo el mapa: el mismo corrimiento que ya usaba el centrado de una ubicación elegida.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas;

/// Dónde se ve el GPS en el mapa, en dp desde el borde de arriba de la pestaña (con el mapa a
/// pantalla completa del arnés, la pestaña mide [alto]).
double _yDelGps(MontajeMapaUbicaciones m, double alto) =>
    alto / 2 - dpBajoElPunto(m.mapa, puntoItalia);

/// Lo que debe cumplirse siempre: el punto azul está a la vista, arriba de la hoja y dentro del mapa.
void _gpsSobreLaHoja(WidgetTester tester, MontajeMapaUbicaciones m) {
  final alto = tester.getSize(find.byKey(const Key('pestana_mapa'))).height;
  final arribaDeLaHoja = tester.getTopLeft(hoja).dy;
  final y = _yDelGps(m, alto);

  expect(dpALaDerechaDelPunto(m.mapa, puntoItalia), closeTo(0, 0.01));
  expect(y, greaterThanOrEqualTo(0), reason: 'el punto azul no sale del mapa por arriba');
  expect(y, lessThan(arribaDeLaHoja), reason: 'el punto azul ($y) quedó debajo de la hoja');
  // Y justo en el medio de lo que la hoja deja libre.
  expect(y, closeTo(arribaDeLaHoja / 2, 0.5));
}

void main() {
  group('el encuadre al abrir', () {
    for (final (nombre, tamano) in [
      ('390x844', const Size(390, 844)),
      ('360x640', const Size(360, 640)),
    ]) {
      testWidgets('con la hoja minimizada el GPS queda arriba de la hoja · $nombre', (
        tester,
      ) async {
        final m = await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso(canvas()),
          tamano: tamano,
        );

        expect(m.mapa.camara!.zoom, MapaAlta.zoomCalle);
        _gpsSobreLaHoja(tester, m);
      });
    }

    testWidgets('sin ubicaciones la hoja sube sola a 1/2 y el GPS no queda debajo de ella (la '
        'lista llega antes que el GPS)', (tester) async {
      final gps = GpsFalso()..bloqueo = Completer<void>();
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(), gps: gps);
      expect(altoHoja(tester), closeTo(844 / 2, 1));

      gps.bloqueo!.complete();
      await asentarLista(tester);

      expect(altoHoja(tester), closeTo(844 / 2, 1));
      _gpsSobreLaHoja(tester, m);
    });

    testWidgets('sin ubicaciones la hoja sube sola a 1/2 y el GPS no queda debajo de ella (el GPS '
        'llega antes que la lista)', (tester) async {
      final repo = RepoListaFalso()..bloqueo = Completer<void>();
      final m = await montarMapaUbicaciones(tester, repo: repo, asentar: false);
      await asentarLista(tester);
      // Todavía sin lista: la hoja está minimizada y el GPS se ve arriba de ella.
      expect(altoHoja(tester), AlturaHoja.altoMinimizada(TextScaler.noScaling));
      _gpsSobreLaHoja(tester, m);

      repo.bloqueo!.complete();
      await asentarLista(tester);

      expect(altoHoja(tester), closeTo(844 / 2, 1));
      _gpsSobreLaHoja(tester, m);
    });

    testWidgets('con error de lectura la hoja sube sola y el GPS sigue a la vista', (tester) async {
      final repo = RepoListaFalso(canvas())..fallaAlSuscribir = true;
      final m = await montarMapaUbicaciones(tester, repo: repo);

      expect(altoHoja(tester), closeTo(844 / 2, 1));
      _gpsSobreLaHoja(tester, m);
    });

    testWidgets('en un teléfono chico (360x640) la hoja a 1/2 que sube sola tampoco lo tapa', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(
        tester,
        repo: RepoListaFalso(),
        tamano: const Size(360, 640),
      );

      _gpsSobreLaHoja(tester, m);
    });

    testWidgets('si el colportor ya movió el mapa, la hoja que sube sola no se lo quita de las '
        'manos', (tester) async {
      final repo = RepoListaFalso()..bloqueo = Completer<void>();
      final m = await montarMapaUbicaciones(tester, repo: repo, asentar: false);
      await asentarLista(tester);
      const aparte = Coordenadas(lat: -34.7, lon: -56.0);
      m.mapa.moverPorGesto(CamaraMapa(centro: aparte, zoom: MapaAlta.zoomCalle));
      await tester.pump();

      repo.bloqueo!.complete();
      await asentarLista(tester);

      expect(altoHoja(tester), closeTo(844 / 2, 1));
      expect(m.mapa.camara!.centro, aparte);
    });
  });

  group('«Mi ubicación»', () {
    for (final (nombre, subidas) in [('minimizada', 0), ('a 1/3', 1), ('a 1/2', 2)]) {
      testWidgets('vuelve al GPS dejándolo arriba de la hoja $nombre', (tester) async {
        final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
        if (subidas > 0) await tocarAsa(tester, subidas);
        m.mapa.moverPorGesto(
          CamaraMapa(centro: const Coordenadas(lat: -34.7, lon: -56.0), zoom: MapaAlta.zoomCalle),
        );
        await tester.pump();

        await tester.tap(botonMiUbicacion);
        await asentarLista(tester);

        _gpsSobreLaHoja(tester, m);
      });
    }

    testWidgets('con la lectura nueva en otro lugar, vuelve a centrar sobre ese lugar sin tapar el '
        'GPS', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await tocarAsa(tester, 2);
      const mas = Coordenadas(lat: -34.88661, lon: -56.13024);
      m.gps.respuesta = Right(lecturaGps(6, punto: mas));

      await tester.tap(botonMiUbicacion);
      await asentarLista(tester);

      final alto = tester.getSize(find.byKey(const Key('pestana_mapa'))).height;
      final y = alto / 2 - dpBajoElPunto(m.mapa, mas);
      expect(y, lessThan(tester.getTopLeft(hoja).dy));
      expect(y, greaterThanOrEqualTo(0));
    });
  });
}

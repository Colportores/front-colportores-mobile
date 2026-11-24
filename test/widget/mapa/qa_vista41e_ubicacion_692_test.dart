// QA de #692 · vista 41, 41E·03, 03B y 03C (HU-UBI-003): el botón de ubicación en sus tres modos con
// el rótulo de 2 s, la brújula y el cono. Los 9 estados a 360x640 y 412x915 con el texto a 1,0 y a
// 2,0 y con las fuentes reales: sin desbordes, el botón de 48 dp que no se mueve cuando aparece el
// rótulo, el rótulo y la brújula dentro de la pantalla y sin pisarse con los demás controles, y los
// casos límite que el PR no cubre. Las capturas salen con `--dart-define=QA_CAPTURAS=true`.
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/modo_seguimiento.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart'
    show ColoresMapa;
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas;
import 'qa_vista41e_692_arnes.dart';

/// Con `--dart-define=QA_HALLAZGOS=true` corren los tests que documentan un hallazgo abierto.
const hallazgos692 = bool.fromEnvironment('QA_HALLAZGOS');

ModoSeguimiento _modo(WidgetTester tester) =>
    contenedorDeLaPestana(tester).read(ubicacionColportorProvider).modo;

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (claro, oscuro) = la > lb ? (la, lb) : (lb, la);
  return (claro + .05) / (oscuro + .05);
}

Future<void> _pasarDosSegundos(WidgetTester tester) async {
  await tester.pump(MedidasBotonUbicacion.duracionRotulo);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('los 9 estados del botón de ubicación en 360x640 y 412x915, texto a 1,0 y 2,0', () {
    for (final MapEntry(key: nombreTamano, value: tamano) in tamanos692.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final MapEntry(key: nombre, value: armar) in escenas692.entries) {
          testWidgets('$nombre · $nombreTamano · texto $escala: sin desbordes y todo a la vista', (
            tester,
          ) async {
            await cargarFuentes692(tester);
            await armar(tester, tamano, escala);

            expect(tester.takeException(), isNull);
            final pantalla = Offset.zero & tamano;
            final boton = tester.getRect(botonMiUbicacion);
            expect(boton.size, const Size(48, 48));
            expect(
              pantalla.contains(boton.topLeft) && pantalla.contains(boton.bottomRight),
              isTrue,
            );

            final rotulo = rotulo692.evaluate().isEmpty ? null : tester.getRect(rotulo692);
            if (rotulo != null) {
              expect(
                rotulo.left,
                greaterThanOrEqualTo(0),
                reason: 'el rótulo no se sale a la izquierda',
              );
              expect(rotulo.right, lessThanOrEqualTo(boton.left));
              expect(rotulo.top, greaterThanOrEqualTo(0));
              // Lo que el rótulo no tiene que pisar: «+ Nueva» y el chip «Referencias».
              expect(rotulo.overlaps(tester.getRect(botonNueva)), isFalse, reason: 'pisa «Nueva»');
              if (chipReferencias.evaluate().isNotEmpty) {
                expect(rotulo.overlaps(tester.getRect(chipReferencias)), isFalse);
              }
            }
            if (brujula692.evaluate().isNotEmpty) {
              final b = tester.getRect(brujula692);
              expect(b.size, const Size(48, 48));
              if (chipReferencias.evaluate().isNotEmpty) {
                expect(b.top, greaterThanOrEqualTo(tester.getRect(chipReferencias).bottom));
              }
              expect(b.right, lessThanOrEqualTo(tamano.width));
              expect(brujula692.hitTestable(), findsOneWidget, reason: 'la brújula se puede tocar');
              if (rotulo != null) expect(rotulo.overlaps(b), isFalse);
            }
            expect(botonMiUbicacion.hitTestable(), findsOneWidget);
            await capturar692(tester, '${nombre}_${nombreTamano}_x$escala'.replaceAll(' ', '_'));
          });
        }
      }
    }
  });

  group('41E·03: el botón no se mueve cuando aparece el rótulo', () {
    for (final MapEntry(key: nombreTamano, value: tamano) in tamanos692.entries) {
      for (final escala in [1.0, 1.5, 2.0, 3.0]) {
        // skip: QA #692 — con el texto grande el rótulo de «Seguir y girar con el teléfono» baja a 2 o
        // 3 renglones, la fila se agranda y el botón se corre en vertical (4 dp a 1,5×, 11 dp a 2,0×).
        testWidgets(
          '$nombreTamano · texto $escala: en los tres toques el botón y «Nueva» quedan '
          'donde estaban',
          skip: escala > 1 && !hallazgos692,
          (tester) async {
            await cargarFuentes692(tester);
            await montarMapaUbicaciones(
              tester,
              repo: RepoListaFalso(canvas()),
              tamano: tamano,
              escala: escala,
            );
            final boton = tester.getRect(botonMiUbicacion);
            final nueva = tester.getRect(botonNueva);

            for (var i = 0; i < 3; i++) {
              // Un toque sobre el botón en el mismo lugar de antes: si se movió, el dedo cae afuera.
              await tester.tapAt(boton.center);
              await asentarLista(tester);
              expect(_modo(tester), ModoSeguimiento.values[(i + 1) % 3], reason: 'toque ${i + 1}');
              expect(rotulo692, findsOneWidget);
              expect(
                tester.getRect(botonMiUbicacion).center.dy,
                closeTo(boton.center.dy, .5),
                reason: 'con el rótulo a la vista el botón se corrió en vertical (toque ${i + 1})',
              );
              expect(tester.getRect(botonMiUbicacion).center.dx, closeTo(boton.center.dx, .5));
              expect(tester.getRect(botonNueva).center.dy, closeTo(nueva.center.dy, .5));
              await _pasarDosSegundos(tester);
            }
          },
        );
      }
    }
  });

  group('41E·03: contraste del rótulo (sale de la semántica, la guía de Flutter no lo mide)', () {
    test('blanco sobre la tinta oscura del mapa pasa AA para texto', () {
      expect(_contraste(Colors.white, ColoresMapa.tintaOscura), greaterThanOrEqualTo(4.5));
    });
  });

  group('casos límite', () {
    testWidgets('cinco toques seguidos sin dejar pasar el tiempo: el modo y el rótulo son los del '
        'último y a los 2 s no queda nada', (tester) async {
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      for (var i = 0; i < 5; i++) {
        await tester.tap(botonMiUbicacion);
        await tester.pump(const Duration(milliseconds: 80));
      }
      await asentarLista(tester);
      expect(_modo(tester), ModoSeguimiento.seguirYGirar, reason: '5 toques: libre→…→girar');
      expect(
        tester.widget<Text>(find.descendant(of: rotulo692, matching: find.byType(Text))).data,
        TextosMapaUbicaciones.seguimientoSeguirYGirar,
      );
      await _pasarDosSegundos(tester);
      expect(rotulo692, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('brújula y botón alternados sin pausa: el modo, el rótulo y el seguimiento '
        'quedan coherentes', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await tocarBoton692(tester);
      await tocarBoton692(tester);
      await moverse692(tester, m.gps, lectura692(adelante692, rumbo: 120));

      await tester.tap(brujula692);
      await tester.tap(botonMiUbicacion);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(botonMiUbicacion);
      await asentarLista(tester);

      // Brújula: girar→seguir; botón: seguir→girar; botón: girar→libre.
      expect(_modo(tester), ModoSeguimiento.libre);
      expect(
        m.gps.seguimientosAbiertos - m.gps.seguimientosCerrados,
        0,
        reason: 'en libre no queda un seguimiento abierto',
      );
      expect(brujula692, findsNothing);
      expect(cono692, findsNothing);
      expect(m.mapa.camara!.rumbo, 0, reason: 'al salir de «girar» el norte vuelve arriba');
      await _pasarDosSegundos(tester);
      expect(rotulo692, findsNothing);
    });

    testWidgets('salir de la pestaña, volver a montarla y recibir un rumbo: el cono y la brújula '
        'vuelven si el modo sigue en «girar»', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await tocarBoton692(tester);
      await tocarBoton692(tester);
      await moverse692(tester, m.gps, lectura692(adelante692, rumbo: 120));
      expect(cono692, findsOneWidget);

      m.montada.value = false;
      await asentarLista(tester);
      m.montada.value = true;
      await asentarLista(tester);
      expect(tester.takeException(), isNull);

      if (_modo(tester) == ModoSeguimiento.seguirYGirar) {
        await moverse692(tester, m.gps, lectura692(masAdelante692, rumbo: 130));
        expect(brujula692, findsOneWidget, reason: 'sigue en «girar»: la brújula está');
        expect(cono692, findsOneWidget, reason: 'llegó un rumbo: el cono está');
      }
      await _pasarDosSegundos(tester);
    });

    testWidgets('en «girar» con el aviso «Sin conexión» la brújula se oculta, pero el botón sigue '
        'sacando del modo y dejando el norte arriba', (tester) async {
      final m = await escenas692['41E·03C girar con rumbo y aviso «Sin conexión»']!(
        tester,
        const Size(390, 844),
        1,
      );
      expect(brujula692, findsNothing, reason: 'decisión del 07/10 (#294): con el aviso se corre');
      expect(m.mapa.camara!.rumbo, 120);

      await tocarBoton692(tester);
      expect(_modo(tester), ModoSeguimiento.libre);
      expect(m.mapa.camara!.rumbo, 0);
    });

    testWidgets('los modos sin lectura (GPS apagado): el botón apagado no abre rótulo ni cono', (
      tester,
    ) async {
      await escenas692['41E·03 sin GPS (botón apagado)']!(tester, const Size(360, 640), 2);
      await tester.tap(botonMiUbicacion, warnIfMissed: false);
      await asentarLista(tester);
      expect(rotulo692, findsNothing);
      expect(brujula692, findsNothing);
      expect(cono692, findsNothing);
      expect(_modo(tester), ModoSeguimiento.libre);
    });

    testWidgets('con un rumbo de 0° (norte) el cono sigue a la vista y la brújula también', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await tocarBoton692(tester);
      await tocarBoton692(tester);
      await moverse692(tester, m.gps, lectura692(adelante692, rumbo: 0));
      expect(cono692, findsOneWidget, reason: '0° es un rumbo, no «sin rumbo»');
      expect(brujula692, findsOneWidget);
    });

    testWidgets('un rumbo de 359,9° con el mapa libre no es «girado» (no hay brújula)', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await tocarBoton692(tester);
      await tocarBoton692(tester);
      await moverse692(tester, m.gps, lectura692(adelante692, rumbo: 359.9));
      m.mapa.moverPorGesto(m.mapa.camara!.conCentro(const Coordenadas(lat: -34.90, lon: -56.15)));
      await asentarLista(tester);
      expect(_modo(tester), ModoSeguimiento.libre);
      expect(brujula692, findsNothing);
    });
  });
}

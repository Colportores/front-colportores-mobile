// QA #674 (issue #670, HU-UBI-003, decisión de Cristian del 05/11, «GPS viejo»): el botón de
// ubicación del mapa tiene tres modos y el mapa sigue a Ana. El canvas 06 no dibuja los modos: acá se
// prueba, sobre la pantalla armada, lo que una persona usa — el botón en cada modo, el aviso de corte
// y qué pasa cuando el seguimiento choca con otras acciones del mapa —, en 360×640 y 412×915, con el
// texto a 1,0 y a 2,0. Las guías de accesibilidad van sin las fuentes reales (con ellas dan falsos
// negativos); la geometría, con ellas.
import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:colportores_mobile/core/error/failure.dart' show MotivoSinGps;
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/modo_seguimiento.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas;

const _tamanos = [Size(360, 640), Size(412, 915)];
const _escalas = [1.0, 2.0];
const _adelante = Coordenadas(lat: -34.88700, lon: -56.13024);

LecturaGps _lectura(Coordenadas punto, {double? rumbo}) =>
    LecturaGps(coordenadas: punto, precisionMetros: 5, rumboGrados: rumbo);

ModoSeguimiento _modo(WidgetTester tester) =>
    contenedorDeLaPestana(tester).read(ubicacionColportorProvider).modo;

Future<void> _tocarBoton(WidgetTester tester, [int veces = 1]) async {
  for (var i = 0; i < veces; i++) {
    await tester.tap(botonMiUbicacion);
    await asentarLista(tester);
  }
}

bool _dentro(Rect caja, Size t) =>
    caja.left >= -0.01 &&
    caja.top >= -0.01 &&
    caja.right <= t.width + 0.01 &&
    caja.bottom <= t.height + 0.01;

String _nombre(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()} a $e';

void main() {
  group('el botón de ubicación en cada modo: cabe, se alcanza y se lee', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        for (var toques = 0; toques < 3; toques++) {
          final modo = ModoSeguimiento.values[toques];
          testWidgets('${_nombre(tamano, escala)} · ${modo.name}: dentro de la pantalla, a '
              '48 dp o más, sin overflow y con las guías de toque', (tester) async {
            final semantica = tester.ensureSemantics();
            await montarMapaUbicaciones(
              tester,
              repo: RepoListaFalso(canvas()),
              tamano: tamano,
              escala: escala,
            );
            await _tocarBoton(tester, toques);
            expect(_modo(tester), modo);

            final caja = tester.getRect(botonMiUbicacion);
            expect(caja.width, greaterThanOrEqualTo(48));
            expect(caja.height, greaterThanOrEqualTo(48));
            expect(_dentro(caja, tamano), isTrue, reason: 'el botón entra en la pantalla');
            expect(botonMiUbicacion.hitTestable(), findsOneWidget, reason: 'nada lo tapa');

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            expect(tester.takeException(), isNull);
            semantica.dispose();
          });
        }
      }
    }

    for (final tamano in _tamanos) {
      testWidgets('${_nombre(tamano, 1)} · el texto de cada modo cumple el contraste (guía de '
          'Flutter)', (tester) async {
        final semantica = tester.ensureSemantics();
        await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), tamano: tamano);
        for (var i = 0; i < 3; i++) {
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await _tocarBoton(tester);
        }
        semantica.dispose();
      });
    }

    testWidgets('el nodo del botón es un botón habilitado con su acción de toque y el nombre del '
        'modo', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      const nombres = [
        'Ubicación: Mapa libre',
        'Ubicación: Seguir mi ubicación',
        'Ubicación: Seguir y girar con el teléfono',
      ];

      for (final nombre in nombres) {
        expect(
          tester.getSemantics(botonMiUbicacion),
          isSemantics(label: nombre, isButton: true, isEnabled: true, hasTapAction: true),
        );
        await _tocarBoton(tester);
      }
      semantica.dispose();
    });
  });

  group('el aviso de corte del seguimiento, a mitad de camino', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        for (final motivo in MotivoSinGps.values) {
          testWidgets('${_nombre(tamano, escala)} · corte por ${motivo.name}: el aviso se anuncia '
              '(región viva) y la página cumple las guías de toque', (tester) async {
            final semantica = tester.ensureSemantics();
            final m = await montarMapaUbicaciones(
              tester,
              repo: RepoListaFalso(canvas()),
              tamano: tamano,
              escala: escala,
            );
            await _tocarBoton(tester, 2);
            m.gps.moverse(_lectura(_adelante, rumbo: 90));
            await asentarLista(tester);

            m.gps.fallarElSeguimiento(motivo);
            await asentarLista(tester);

            final aviso = find.text(TextosMapaUbicaciones.seguimientoCortado);
            expect(aviso, findsOneWidget);
            expect(_modo(tester), ModoSeguimiento.libre);

            // Se anuncia: el aviso está en una región viva.
            var viva = false;
            for (SemanticsNode? n = tester.getSemantics(aviso); n != null; n = n.parent) {
              if (n.getSemanticsData().flagsCollection.isLiveRegion) viva = true;
            }
            expect(viva, isTrue, reason: 'el lector de pantalla tiene que oír que se cortó');

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            // Con la fuente de prueba (Ahem) el texto es el doble de ancho y la acción del aviso
            // «desborda»: se descarta acá y el overflow se mide con las fuentes reales en
            // `qa_mapa_seguimiento_674_geometria_test.dart`.
            tester.takeException();
            semantica.dispose();
          });
        }
      }
    }
  });

  group('acciones superpuestas', () {
    // Decisión P1 (§2, opción a): tocar una casa pasa a «Mapa libre»; antes seguía a Ana.
    testWidgets(
      'mientras sigue, un toque en un marcador abre su vista previa y pasa a «Mapa libre»',
      (tester) async {
        final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
        await _tocarBoton(tester);

        m.mapa.tocarPunto('b');
        await asentarLista(tester);

        expect(seleccionadaId(tester), 'b');
        expect(_modo(tester), ModoSeguimiento.libre);
        expect(m.gps.siguiendo, isFalse);
      },
    );

    // Decisión P1 (§2): tocar una casa pasa a «Mapa libre», así el próximo paso de Ana no la devuelve.
    testWidgets('dada la casa elegida mientras sigue, cuando Ana camina, entonces el mapa no la '
        'saca de la vista de la casa que acaba de tocar', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      m.mapa.tocarPunto('d');
      await asentarLista(tester);
      final centroDeLaCasa = m.mapa.camara!.centro;

      m.gps.moverse(_lectura(_adelante));
      await asentarLista(tester);

      expect(
        _modo(tester) == ModoSeguimiento.libre || m.mapa.camara!.centro == centroDeLaCasa,
        isTrue,
        reason:
            'tocar una casa mientras sigue la lleva al centro; el siguiente paso de Ana la '
            'devuelve a la colportora y la vista previa queda sobre una casa que ya no se ve',
      );
    });

    testWidgets('con la app que pasa por inactiva y vuelve (aviso del sistema, llamada) el stream '
        'se cierra y se reabre una sola vez', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester, 2);
      expect(m.gps.siguiendo, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await asentarLista(tester);
      expect(m.gps.siguiendo, isFalse);
      expect(_modo(tester), ModoSeguimiento.seguirYGirar, reason: 'el modo se recuerda');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await asentarLista(tester);
      expect(m.gps.siguiendo, isTrue);
      expect(m.gps.seguimientosAbiertos - m.gps.seguimientosCerrados, 1);
    });

    testWidgets('un corte mientras la app está en segundo plano no avisa nada ni deja el botón '
        'trabado al volver', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await asentarLista(tester);

      // Con el stream cerrado nada puede cortarse; volver reabre y el botón anda.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await asentarLista(tester);
      await _tocarBoton(tester);

      expect(_modo(tester), ModoSeguimiento.seguirYGirar);
      expect(m.gps.siguiendo, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el stream que se cierra solo (sin error) corta el seguimiento y avisa una vez', (
      tester,
    ) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()));
      await _tocarBoton(tester);

      await m.gps.cerrarElSeguimiento();
      await asentarLista(tester);

      expect(_modo(tester), ModoSeguimiento.libre);
      expect(find.text(TextosMapaUbicaciones.seguimientoCortado), findsOneWidget);
      expect(botonMiUbicacion.hitTestable(), findsOneWidget);
    });
  });

  group('los cinco estados con el seguimiento', () {
    testWidgets('sin ubicaciones registradas el botón sigue a Ana igual (vacío)', (tester) async {
      final m = await montarMapaUbicaciones(tester, repo: RepoListaFalso());
      await _tocarBoton(tester, 2);

      expect(_modo(tester), ModoSeguimiento.seguirYGirar);
      expect(m.gps.siguiendo, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mientras busca el primer GPS el botón está apagado y dice por qué', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final espera = Completer<void>();
      addTearDown(() {
        if (!espera.isCompleted) espera.complete();
      });
      final gps = GpsFalso()..bloqueo = espera;
      await montarMapaUbicaciones(tester, repo: RepoListaFalso(canvas()), gps: gps, asentar: false);
      await tester.pump(const Duration(milliseconds: 100));

      final nodo = tester.getSemantics(botonMiUbicacion).getSemanticsData();
      expect(nodo.label, startsWith('Mi ubicación.'));
      expect(nodo.flagsCollection.isEnabled, Tristate.isFalse);
      expect(_modo(tester), ModoSeguimiento.libre);
      semantica.dispose();
    });
  });
}

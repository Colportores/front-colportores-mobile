// QA de #286 / PR #288 (mapa base MapLibre bajo las vistas 03 y 04): lo que la suite del PR no mide.
//
// - Las guías de accesibilidad (toque Android e iOS, etiquetas, contraste) en cada estado del canvas
//   (03A · 01 a 04 y 04B · 01 a 03), en 360×640 y 412×915, con texto 1.0, 1.3 y 2.0.
// - Casos límite con el mapa nuevo: el teclado abierto, un toque justo sobre el punto azul y mover
//   el mapa mientras el alta se está guardando.
//
// MapLibre no se dibuja en `flutter test`: el mapa es la vista falsa de `mapa_base_falso.dart`. Lo que
// dibuja la vista nativa (capas, punto azul, radio, atribución, gestos reales) queda para la prueba
// manual en un dispositivo.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:dartz/dartz.dart' show Right;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart' show asentar, gpsSinPermiso;
import '../../helpers/mapa_base_falso.dart';

class _Anfitrion extends StatelessWidget {
  const _Anfitrion(this.salidas);

  final List<SalidaAltaUbicacion?> salidas;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async =>
            salidas.add(await AltaUbicacionPage.abrir(context, colportorId: 'col-1')),
        child: const Text('abrir'),
      ),
    ),
  );
}

class _Mundo {
  _Mundo({GpsFalso? gps, RepoAltaFalso? repo})
    : gps = gps ?? GpsFalso(),
      repo = repo ?? RepoAltaFalso();

  final GpsFalso gps;
  final RepoAltaFalso repo;
  final mapa = FabricaMapaFalsa();
  final salidas = <SalidaAltaUbicacion?>[];
}

Future<_Mundo> _montar(
  WidgetTester tester, {
  GpsFalso? gps,
  RepoAltaFalso? repo,
  double escala = 1,
  Size tamano = const Size(360, 640),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetViewInsets);
  final m = _Mundo(gps: gps, repo: repo);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        gps: m.gps,
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1234'),
        ),
        repo: m.repo,
        ahora: DateTime.utc(2026, 10, 2, 12),
        mapa: m.mapa,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: _Anfitrion(m.salidas),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await asentar(tester);
  return m;
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.pump();
  if (f.hitTestable().evaluate().isEmpty) {
    await Scrollable.ensureVisible(tester.element(f), alignment: .5);
    await tester.pump();
  }
  await tester.tap(f);
  await asentar(tester);
}

Finder get _registrar => find.widgetWithText(FilledButton, TextosAlta.registrar);

Finder get _mapa => find.byType(MapaBase).first;

/// Los estados del canvas (vistas 03 y 04) a los que se llega desde el alta.
enum _Estado {
  gpsPreciso('03A · 01 GPS preciso'),
  sinGps('03A · 02 Sin GPS'),
  gpsImpreciso('03A · 03 GPS impreciso'),
  unaCandidata('04B · 01 Una candidata'),
  variasCandidatas('04B · 02 Más de una candidata'),
  justificacion('04B · 03 Crear igual con justificación');

  const _Estado(this.rotulo);
  final String rotulo;
}

Future<_Mundo> _hasta(
  WidgetTester tester,
  _Estado estado, {
  double escala = 1,
  Size tamano = const Size(360, 640),
}) async {
  RepoAltaFalso? repo;
  GpsFalso? gps;
  switch (estado) {
    case _Estado.gpsPreciso:
      break;
    case _Estado.sinGps:
      gps = gpsSinPermiso;
    case _Estado.gpsImpreciso:
      gps = GpsFalso(Right(lecturaGps(85)));
    case _Estado.unaCandidata:
    case _Estado.justificacion:
      repo = RepoAltaFalso()
        ..comportamiento = (_) async => Right(AltaConDuplicados(candidatas: [candidata('a')]));
    case _Estado.variasCandidatas:
      repo = RepoAltaFalso()
        ..comportamiento = (_) async =>
            Right(AltaConDuplicados(candidatas: [candidata('a'), candidata('b', metros: 4)]));
  }
  final m = await _montar(tester, gps: gps, repo: repo, escala: escala, tamano: tamano);
  switch (estado) {
    case _Estado.gpsPreciso:
    case _Estado.sinGps:
      break;
    case _Estado.gpsImpreciso:
      await _tocar(tester, find.text('Casa'));
    case _Estado.unaCandidata:
    case _Estado.variasCandidatas:
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);
    case _Estado.justificacion:
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);
      await _tocar(tester, find.text('Crear igual'));
      expect(find.text('¿Por qué es otra ubicación?'), findsOneWidget);
  }
  return m;
}

void main() {
  group('QA #286 · accesibilidad de cada artboard del canvas, con el mapa nuevo', () {
    for (final tamano in [const Size(360, 640), const Size(412, 915)]) {
      for (final escala in [1.0, 1.3, 2.0]) {
        for (final estado in _Estado.values) {
          testWidgets('${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()} y texto '
              '${escala}x: sin desborde y con las cuatro guías', (tester) async {
            final handle = tester.ensureSemantics();
            await _hasta(tester, estado, escala: escala, tamano: tamano);

            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            handle.dispose();
          });
        }
      }
    }
  });

  group('QA #286 · el mapa del alta en los casos límite', () {
    testWidgets(
      'un toque justo sobre el punto azul llega al mapa: el punto queda «Marcado a mano»',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(tester);
        await tester.pumpAndSettle();
        final nodo = find.bySemanticsLabel('Tu ubicación');
        expect(nodo, findsOneWidget);
        expect(find.text('Marcado a mano'), findsNothing);

        // El nodo de «Tu ubicación» no atrapa el toque (no es un botón): el mapa lo recibe.
        await tester.tapAt(tester.getCenter(nodo));
        await asentar(tester, 10);

        expect(find.text('Marcado a mano'), findsOneWidget);
        expect(tester.takeException(), isNull);
        handle.dispose();
      },
    );

    testWidgets('con el teclado abierto el mapa se achica sin desbordar y «Tu ubicación» sigue '
        'dentro del mapa', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(tester);
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final nodo = find.bySemanticsLabel('Tu ubicación');
      expect(nodo, findsOneWidget);
      final mapa = tester.getRect(_mapa);
      expect(mapa.contains(tester.getCenter(nodo)), isTrue, reason: '$mapa no contiene el nodo');
      handle.dispose();
    });

    testWidgets('mover el mapa mientras el alta se guarda: se guarda el punto confirmado y no se '
        'pierde nada', (tester) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final m = await _montar(tester, repo: repo);
      await tester.pumpAndSettle();
      await _tocar(tester, find.text('Casa'));
      await Scrollable.ensureVisible(tester.element(_registrar), alignment: .5);
      await tester.pump();
      await tester.tap(_registrar);
      await tester.pump();
      expect(find.text('Registrando…'), findsOneWidget);
      final confirmado = repo.llamadas.single.ubicacion;

      // Con el alta en vuelo el colportor arrastra el mapa.
      final destino = CamaraMapa(
        centro: Coordenadas(lat: puntoItalia.lat + 0.002, lon: puntoItalia.lon),
        zoom: m.mapa.camara!.zoom,
      );
      m.mapa.moverPorGesto(destino);
      await asentar(tester);
      repo.bloqueo!.complete();
      await asentar(tester, 10);

      expect(tester.takeException(), isNull);
      expect(repo.llamadas, hasLength(1), reason: 'una sola alta');
      expect(repo.llamadas.single.ubicacion.lat, confirmado.lat);
      expect(repo.llamadas.single.ubicacion.lon, confirmado.lon);
      expect(m.salidas, hasLength(1));
      expect(m.salidas.single, isA<UbicacionCreada>());
    });

    testWidgets('volver atrás con el mapa en pleno pellizco no deja timers ni errores', (
      tester,
    ) async {
      await _montar(tester);
      await tester.pumpAndSettle();
      final centro = tester.getCenter(_mapa);
      final a = await tester.startGesture(centro - const Offset(40, 0), pointer: 1);
      final b = await tester.startGesture(centro + const Offset(40, 0), pointer: 2);
      await a.moveBy(const Offset(-30, 0));
      await b.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 16));

      await tester.binding.handlePopRoute();
      await a.up();
      await b.up();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
    });
  });
}

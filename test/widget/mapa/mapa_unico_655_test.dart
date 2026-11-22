import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/mapa_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_principal_provider.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/ruta_capa_del_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/mapa_base_falso.dart';
import 'mapa_ubicaciones_arnes.dart';

/// Cuántas vistas nativas de mapa hay montadas (en los tests, la falsa reemplaza a MapLibre).
int vistasDeMapaMontadas() => find.byType(VistaMapaFalsa, skipOffstage: false).evaluate().length;

/// Un «mapa» que cuenta los toques y los arrastres, debajo de la capa.
final class _MapaQueCuenta {
  var toques = 0;
  var arrastres = 0;

  Widget get widget => Semantics(
    label: 'Mapa',
    container: true,
    child: GestureDetector(
      key: const Key('mapa'),
      behavior: HitTestBehavior.opaque,
      onTap: () => toques++,
      onPanUpdate: (_) => arrastres++,
      child: const ColoredBox(color: Colors.green, child: SizedBox.expand()),
    ),
  );
}

/// La hoja de la capa: 200 dp abajo, con un botón.
Widget _hoja(BuildContext context) => Align(
  alignment: Alignment.bottomCenter,
  child: Material(
    key: const Key('hoja'),
    color: Colors.white,
    child: SizedBox(
      height: 200,
      width: double.infinity,
      child: Center(
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(7),
          child: const Text('Guardar posición'),
        ),
      ),
    ),
  ),
);

Future<NavigatorState> _montarConCapa(WidgetTester tester, _MapaQueCuenta mapa) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final navegador = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navegador,
      home: Scaffold(body: mapa.widget),
    ),
  );
  return navegador.currentState!;
}

void main() {
  group('RutaCapaDelMapa: la hoja va encima del mismo mapa (vista 41)', () {
    testWidgets('tocar fuera de la hoja toca el mapa de abajo; tocar la hoja, no', (tester) async {
      final mapa = _MapaQueCuenta();
      final navegador = await _montarConCapa(tester, mapa);
      int? salida;
      unawaited(
        navegador
            .push<int>(
              RutaCapaDelMapa(
                settings: const RouteSettings(name: 'mapa/capa'),
                builder: _hoja,
              ),
            )
            .then((valor) => salida = valor),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(195, 200));
      await tester.pump();
      expect(mapa.toques, 1, reason: 'el mapa sigue tocable con la capa encima');

      await tester.tapAt(const Offset(30, 844 - 30));
      await tester.pump();
      expect(mapa.toques, 1, reason: 'la hoja se queda con los toques sobre ella');

      await tester.tap(find.text('Guardar posición'));
      await tester.pumpAndSettle();
      expect(salida, 7);
      expect(mapa.toques, 1);
    });

    testWidgets('el mapa se sigue arrastrando con la capa abierta', (tester) async {
      final mapa = _MapaQueCuenta();
      final navegador = await _montarConCapa(tester, mapa);
      unawaited(
        navegador.push<void>(
          RutaCapaDelMapa(
            settings: const RouteSettings(name: 'mapa/capa'),
            builder: _hoja,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragFrom(const Offset(195, 300), const Offset(-80, 40));
      await tester.pump();

      expect(mapa.arrastres, greaterThan(0));
    });

    testWidgets('el lector de pantalla sigue encontrando el mapa debajo de la capa', (
      tester,
    ) async {
      final lector = tester.ensureSemantics();
      final mapa = _MapaQueCuenta();
      final navegador = await _montarConCapa(tester, mapa);
      unawaited(
        navegador.push<void>(
          RutaCapaDelMapa(
            settings: const RouteSettings(name: 'mapa/capa'),
            builder: _hoja,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Mapa'), findsOneWidget);
      expect(find.text('Guardar posición'), findsOneWidget);
      lector.dispose();
    });

    testWidgets('el atrás del teléfono la cierra y el mapa queda como estaba', (tester) async {
      final mapa = _MapaQueCuenta();
      final navegador = await _montarConCapa(tester, mapa);
      unawaited(
        navegador.push<void>(
          RutaCapaDelMapa(
            settings: const RouteSettings(name: 'mapa/capa'),
            builder: _hoja,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hoja')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hoja')), findsNothing);
      expect(find.byKey(const Key('mapa')), findsOneWidget);
    });

    testWidgets('abrir y cerrar dos capas seguidas no deja ninguna trabada', (tester) async {
      final mapa = _MapaQueCuenta();
      final navegador = await _montarConCapa(tester, mapa);
      for (var i = 0; i < 2; i++) {
        unawaited(
          navegador.push<void>(
            RutaCapaDelMapa(
              settings: const RouteSettings(name: 'mapa/capa'),
              builder: _hoja,
            ),
          ),
        );
        await tester.pumpAndSettle();
        navegador.pop();
        await tester.pumpAndSettle();
      }

      expect(find.byKey(const Key('hoja')), findsNothing);
      await tester.tapAt(const Offset(195, 700));
      await tester.pump();
      expect(mapa.toques, 1);
    });
  });

  group('Mapa principal (#655)', () {
    testWidgets('la pestaña Mapa entrega su cámara al mapa principal y hay una sola vista nativa', (
      tester,
    ) async {
      final montaje = await montarMapaUbicaciones(tester);
      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(MapaUbicacionesPage)),
      );
      final principal = contenedor.read(mapaPrincipalProvider.notifier);

      expect(principal.hayMapa(), isTrue);
      expect(principal.camara(), isNotNull);
      expect(contenedor.read(mapaPrincipalProvider), const Explorando());
      expect(vistasDeMapaMontadas(), 1);
      expect(montaje.mapa.armada, isTrue);
    });

    testWidgets('una capa que pide ir a una casa mueve la cámara de la pestaña Mapa', (
      tester,
    ) async {
      final montaje = await montarMapaUbicaciones(tester);
      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(MapaUbicacionesPage)),
      );
      final principal = contenedor.read(mapaPrincipalProvider.notifier);
      final antes = montaje.mapa.movimientos.length;
      final destino = CamaraMapa(centro: principal.camara()!.centro, zoom: 17);

      await principal.llevarA(destino, por: IntencionCamara.elegirCasa);
      await tester.pump();

      expect(montaje.mapa.movimientos.length, antes + 1);
      expect(montaje.mapa.movimientos.last.zoom, 17);
    });

    testWidgets('al desmontarse la pestaña el mapa principal queda sin mapa', (tester) async {
      await montarMapaUbicaciones(tester);
      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(MapaUbicacionesPage)),
      );
      final principal = contenedor.read(mapaPrincipalProvider.notifier);
      expect(principal.hayMapa(), isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(principal.hayMapa(), isFalse);
    });
  });
}

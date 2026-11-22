// QA de «Mapas offline» (vista 35, HU-SYNC-010, #132): guías de accesibilidad de Flutter en cada
// artboard y en los dos teléfonos de la matriz (360x640 y 412x915), y los casos límite que los
// tests de la implementación no cubren. Va con la fuente de prueba (bloques llenos): con la real el
// suavizado de los trazos finos da falsos rojos en el contraste.
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mapa_descargas_arnes.dart';
import '../helpers/qa_mapas_offline_132_arnes.dart';
import '../helpers/tiles_falsos.dart';

void main() {
  for (final tamano in [qaChico, qaGrande]) {
    final t = '${tamano.width.toInt()}x${tamano.height.toInt()}';
    group('QA #132 · accesibilidad a $t', () {
      for (final estado in QaEstado.values) {
        testWidgets('${estado.name}: guías de toque, etiqueta y contraste', (tester) async {
          await qaLlegar(tester, estado, tamano: tamano);
          expect(tester.takeException(), isNull);
          await qaGuias(tester);
        });
      }

      testWidgets('35-10: la hoja de la sugerencia cumple las guías', (tester) async {
        await qaMontarSugerencia(tester, tamano: tamano);
        expect(find.byKey(const Key('sugerencia_mapa_hoja')), findsOneWidget);
        await qaGuias(tester);
      });
    });
  }

  group('QA #132 · opción elegida de la pantalla 01', () {
    // La opción elegida usa un fondo tenue explícito: las guías de Flutter no ven su contraste
    // porque la opción usa `excludeSemantics`, por eso se mide acá.
    testWidgets('el título y el detalle de «Mi zona» elegida se leen (contraste >= 4,5:1)', (
      tester,
    ) async {
      await qaLlegar(tester, QaEstado.e01);
      final titulo = tester.widget<Text>(find.text('Mi zona'));
      final detalle = tester.widget<Text>(find.text('Cerro Norte · 14 MB'));
      final fondo = tester
          .widget<Material>(
            find.ancestor(of: find.text('Mi zona'), matching: find.byType(Material)).first,
          )
          .color!;
      expect(qaContraste(titulo.style!.color!, fondo), greaterThanOrEqualTo(4.5));
      expect(qaContraste(detalle.style!.color!, fondo), greaterThanOrEqualTo(4.5));
    });

    testWidgets('el ícono de la opción elegida se distingue del fondo (>= 3:1)', (tester) async {
      await qaLlegar(tester, QaEstado.e01);
      final icono = tester.widget<Icon>(find.byIcon(Icons.radio_button_checked));
      final fondo = tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.byIcon(Icons.radio_button_checked),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      expect(qaContraste(icono.color!, fondo), greaterThanOrEqualTo(3));
    });
  });

  group('QA #132 · casos límite', () {
    testWidgets('doble toque en «Borrar mapa» abre una sola hoja y no borra hasta confirmar', (
      tester,
    ) async {
      final arnes = ArnesMapa(catalogo: [qaCiudad86], servirPaqueteMontevideo: false);
      await arnes.repositorio.registrar(descargadoDe(qaCiudad86));
      await qaMontar(tester, arnes: arnes);

      await tester.tap(qaClave('mapas_offline_borrar_ciudad-montevideo'));
      await tester.tap(qaClave('mapas_offline_borrar_ciudad-montevideo'), warnIfMissed: false);
      await qaAsentar(tester);

      expect(qaClave('mapas_offline_hoja_borrar'), findsOneWidget);
      expect(find.text('¿Borrar el mapa de Montevideo?'), findsOneWidget);
      expect(arnes.repositorio.registrados, isNotEmpty);

      await tester.tap(qaClave('mapas_offline_borrar_cancelar'));
      await qaAsentar(tester);
      expect(qaClave('mapas_offline_hoja_borrar'), findsNothing);
      expect(arnes.repositorio.registrados, isNotEmpty);
      expect(qaClave('mapas_offline_tarjeta_ciudad-montevideo'), findsOneWidget);

      await tester.tap(qaClave('mapas_offline_borrar_ciudad-montevideo'));
      await qaAsentar(tester);
      await tester.tap(qaClave('mapas_offline_borrar_confirmar'));
      await qaAsentar(tester);
      expect(arnes.repositorio.registrados, isEmpty);
      expect(qaClave('mapas_offline_falla'), findsNothing);
    });

    testWidgets('doble toque en «Actualizar» pide la versión nueva una sola vez', (tester) async {
      final v1 = paqueteDe(
        qaBytes,
        id: 'ciudad-montevideo',
        nivel: NivelCobertura.ciudad,
        ambitoId: 'c-1',
        version: 'v1',
      );
      final v2 = paqueteDe(
        qaBytes,
        id: 'ciudad-montevideo',
        nivel: NivelCobertura.ciudad,
        ambitoId: 'c-1',
        version: 'v2',
      );
      final arnes = ArnesMapa(catalogo: [v2], servirPaqueteMontevideo: false)
        ..servidor.archivos[v2.origen] = qaBytes
        ..servidor.retenerDespuesDe = 2000;
      await arnes.repositorio.registrar(descargadoDe(v1));
      await qaMontar(tester, arnes: arnes);

      await tester.tap(find.text('Actualizar'));
      await tester.tap(find.text('Actualizar'), warnIfMissed: false);
      await qaAsentar(tester);

      expect(arnes.servidor.pedidos, [0]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('doble toque en «Borrar mapa» no deja un aviso de error', (tester) async {
      final arnes = ArnesMapa(catalogo: [qaCiudad86], servirPaqueteMontevideo: false);
      await arnes.repositorio.registrar(descargadoDe(qaCiudad86));
      await qaMontar(tester, arnes: arnes);

      await tester.tap(qaClave('mapas_offline_borrar_ciudad-montevideo'));
      await qaAsentar(tester);
      await tester.tap(qaClave('mapas_offline_borrar_confirmar'));
      await tester.tap(qaClave('mapas_offline_borrar_confirmar'), warnIfMissed: false);
      await qaAsentar(tester);

      expect(arnes.repositorio.registrados, isEmpty);
      expect(qaClave('mapas_offline_falla'), findsNothing);
      expect(find.text('MAPAS OFFLINE · 01'), findsOneWidget);
    });

    testWidgets('«Pausar» dos veces seguidas deja una sola pausa y «Seguir» disponible', (
      tester,
    ) async {
      final arnes = ArnesMapa(catalogo: [qaCiudadReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[qaCiudadReal.origen] = qaBytes
        ..servidor.retenerDespuesDe = 2000;
      await qaMontar(tester, arnes: arnes, lugar: const Right(qaSinZona));
      await tester.tap(qaClave('mapas_offline_descargar'));
      await qaAsentar(tester);

      await tester.tap(qaClave('mapas_offline_pausar_ciudad-montevideo'));
      await tester.tap(qaClave('mapas_offline_pausar_ciudad-montevideo'), warnIfMissed: false);
      await qaAsentar(tester);

      expect(find.text('En pausa'), findsOneWidget);
      expect(find.text('Pausada. Tocá Seguir para continuar.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con la descarga en marcha, «Cambiar cobertura» y volver no pierde la tarjeta', (
      tester,
    ) async {
      final arnes = ArnesMapa(catalogo: [qaCiudadReal], servirPaqueteMontevideo: false)
        ..servidor.archivos[qaCiudadReal.origen] = qaBytes
        ..servidor.retenerDespuesDe = 2000;
      await qaMontar(tester, arnes: arnes, lugar: const Right(qaSinZona));
      await tester.tap(qaClave('mapas_offline_descargar'));
      await qaAsentar(tester);

      await tester.tap(qaClave('mapas_offline_cambiar_cobertura'));
      await qaAsentar(tester);
      expect(find.text('MAPAS OFFLINE · 01'), findsOneWidget);
      await tester.tap(qaClave('mapas_offline_atras'));
      await qaAsentar(tester);

      expect(find.text('MAPAS OFFLINE · 02'), findsOneWidget);
      expect(qaClave('mapas_offline_pausar_ciudad-montevideo'), findsOneWidget);
    });

    testWidgets('el nombre de la ciudad pegado muy largo no desborda la tarjeta ni la elección', (
      tester,
    ) async {
      final largo = 'Ñandú 🗺️ ' * 40;
      final p = qaPaquete('ciudad-montevideo', NivelCobertura.ciudad, 'c-1', largo, 86);
      final arnes = ArnesMapa(catalogo: [p], servirPaqueteMontevideo: false);
      await arnes.repositorio.registrar(descargadoDe(p));
      await qaMontar(tester, arnes: arnes, escala: 2);
      expect(tester.takeException(), isNull);
    });
  });
}

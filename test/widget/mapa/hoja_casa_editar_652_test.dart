// Vista 39, hoja de la casa (C·01 y C·02) con «Editar casa» junto a la dirección (decisión de Cristian,
// 04/11, #652): abre la edición de la ubicación (vista 07) y, al guardar o cancelar, la hoja sigue
// abierta, con la dirección nueva y sin cerrarse. El canvas de la 39 no dibuja el botón.
//
// Casos límite: sin colportor o con la casa de baja no se ofrece, doble toque, falla al abrir (la hoja
// avisa y el botón vuelve a andar), volver con cualquier salida, texto al 200 % y área táctil de 48 dp.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;

/// Lo que se le pidió abrir al abridor de la edición.
typedef _Apertura = ({String colportorId, String ubicacionId});

class _Escenario {
  final aperturas = <_Apertura>[];
  final cierres = <int>[];
  final item = ValueNotifier<ItemListaUbicacion>(itemDeLaHoja());
}

Future<_Escenario> _montar(
  WidgetTester tester, {
  Future<SalidaModificarUbicacion?> Function(_Escenario e)? alAbrir,
  ItemListaUbicacion? item,
  String? colportorId = 'col-1',
  double escala = 1,
  bool arriba = false,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = _Escenario();
  if (item != null) e.item.value = item;
  addTearDown(e.item.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...overridesHojaCasa(),
        abridorEdicionUbicacionProvider.overrideWithValue((
          context, {
          required String colportorId,
          required String ubicacionId,
        }) {
          e.aperturas.add((colportorId: colportorId, ubicacionId: ubicacionId));
          return alAbrir == null ? Future.value() : alAbrir(e);
        }),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            // La hoja sigue a la lista: lo que cambia en `item` es lo que la lista viva le da.
            child: ValueListenableBuilder<ItemListaUbicacion>(
              valueListenable: e.item,
              builder: (_, item, _) => HojaCasa(
                item: item,
                ahora: ahoraLista,
                alCerrar: () => e.cierres.add(e.cierres.length),
                colportorId: colportorId,
                arriba: arriba,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return e;
}

Finder get _editar => find.byKey(ClavesHojaCasa.editar);

Future<void> _asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  group('C·01 · «Editar casa» junto a la dirección', () {
    testWidgets('dado un colportor con sesión, la hoja ofrece «Editar casa» junto a la dirección, '
        'con una etiqueta que dice cuál casa y un área de 48 dp', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);

      expect(_editar, findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byKey(ClavesHojaCasa.titulo), findsOneWidget);
      // Junto a la dirección: en la misma fila de la cabecera, arriba, no entre los botones de abajo.
      expect(
        (tester.getCenter(_editar).dy - tester.getCenter(find.byKey(ClavesHojaCasa.titulo)).dy)
            .abs(),
        lessThan(24),
        reason: 'en la misma fila que la dirección',
      );
      final caja = tester.getSize(_editar);
      expect(caja.height, greaterThanOrEqualTo(48));
      expect(caja.width, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(_editar).label,
        'Editar casa: Grecia 3310',
        reason: 'el lector dice qué casa se edita',
      );
      expect(find.byTooltip('Editar casa'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('dado que no se sabe quién es el colportor, no se ofrece (sin destino)', (
      tester,
    ) async {
      await _montar(tester, colportorId: null);

      expect(_editar, findsNothing);
    });

    testWidgets('dado una casa dada de baja, no se ofrece (esa se reactiva)', (tester) async {
      await _montar(tester, item: itemDeLaHoja(baja: DateTime.utc(2026, 10, 1)));

      expect(_editar, findsNothing);
    });

    testWidgets('dado un toque, abre la edición de esa ubicación con el colportor y la hoja sigue '
        'abierta', (tester) async {
      final e = await _montar(tester);

      await tester.tap(_editar);
      await _asentar(tester);

      expect(e.aperturas, [(colportorId: 'col-1', ubicacionId: 'u-1')]);
      expect(e.cierres, isEmpty);
      expect(_editar, findsOneWidget);
    });

    testWidgets('dado que se guardó (UbicacionEditada), al volver la hoja sigue abierta y muestra '
        'la dirección nueva sin cerrarse', (tester) async {
      final e = await _montar(
        tester,
        alAbrir: (e) async {
          // La edición guardó: la lista viva ya trae la casa con la dirección corregida.
          e.item.value = itemDeLaHoja(calle: 'Rivera', numero: '1500');
          return UbicacionEditada(e.item.value.ubicacion);
        },
      );
      expect(find.text('Grecia 3310'), findsOneWidget);

      await tester.tap(_editar);
      await _asentar(tester);

      expect(find.text('Rivera 1500'), findsOneWidget);
      expect(find.text('Grecia 3310'), findsNothing);
      expect(e.cierres, isEmpty);
      expect(_editar, findsOneWidget);
    });

    testWidgets('dado que se cerró la edición sin guardar (null) o con otra salida, la hoja sigue '
        'abierta y se puede volver a editar', (tester) async {
      var vez = 0;
      final e = await _montar(
        tester,
        alAbrir: (_) async => ++vez == 1 ? null : const UbicacionExistenteElegida('u-2'),
      );

      await tester.tap(_editar);
      await _asentar(tester);
      await tester.tap(_editar);
      await _asentar(tester);

      expect(e.aperturas, hasLength(2));
      expect(e.cierres, isEmpty);
      expect(_editar, findsOneWidget);
    });

    testWidgets('dado un doble toque mientras la edición está abierta, se abre una sola vez', (
      tester,
    ) async {
      final compuerta = Completer<SalidaModificarUbicacion?>();
      final e = await _montar(tester, alAbrir: (_) => compuerta.future);

      await tester.tap(_editar);
      await tester.tap(_editar, warnIfMissed: false);
      await tester.pump();
      compuerta.complete(null);
      await _asentar(tester);

      expect(e.aperturas, hasLength(1));
    });

    testWidgets('dado que no se pudo abrir la edición, la hoja avisa qué hacer, sigue abierta y el '
        'botón vuelve a poder tocarse', (tester) async {
      var vez = 0;
      final e = await _montar(
        tester,
        alAbrir: (_) async {
          if (++vez == 1) throw StateError('no abrió');
          return null;
        },
      );

      await tester.tap(_editar);
      await _asentar(tester);

      expect(find.text('No pudimos abrir la edición. Probá de nuevo.'), findsOneWidget);
      expect(e.cierres, isEmpty);

      await tester.tap(_editar);
      await _asentar(tester);

      expect(e.aperturas, hasLength(2));
      expect(find.text('No pudimos abrir la edición. Probá de nuevo.'), findsNothing);
    });

    testWidgets('dado texto al 200 % en un teléfono chico, la cabecera no desborda y el botón se '
        've y se toca', (tester) async {
      final e = await _montar(tester, escala: 2, tamano: const Size(320, 640));

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_editar);
      await tester.tap(_editar);
      await _asentar(tester);

      expect(e.aperturas, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado la hoja arriba (C·02), «Editar casa» también está junto a la dirección', (
      tester,
    ) async {
      final e = await _montar(tester, arriba: true);

      expect(find.byKey(ClavesHojaCasa.pestanas), findsOneWidget, reason: 'es la hoja arriba');
      expect(_editar, findsOneWidget);
      await tester.tap(_editar);
      await _asentar(tester);
      expect(e.aperturas, hasLength(1));
    });
  });
}

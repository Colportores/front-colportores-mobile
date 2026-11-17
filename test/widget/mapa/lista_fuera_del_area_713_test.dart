// La pestaña «Lista» (vista 05) y las casas fuera del área (#713; decisión del 17/11, P1 §2 del QA de
// #715): la fila lleva la etiqueta «FUERA DE TU ÁREA», la misma pieza que en «Cercanía», y la Lista no
// oculta ninguna (ver u ocultar es solo del mapa).
import 'dart:async';

import 'package:colportores_mobile/features/mapa/presentation/providers/fuera_del_area_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_fuera_del_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart';

Finder _fila(String id) => find.byKey(ValueKey(id));

Finder _etiquetaEn(String id) =>
    find.descendant(of: _fila(id), matching: find.byType(EtiquetaFueraDelArea));

void main() {
  late StreamController<Set<String>> marcas;

  setUp(() => marcas = StreamController<Set<String>>.broadcast());
  tearDown(() => marcas.close());

  Future<void> montar(
    WidgetTester tester,
    Set<String> iniciales, {
    double escala = 1,
    bool casaAbreSuHoja = false,
  }) => montarLista(
    tester,
    casaAbreSuHoja: casaAbreSuHoja,
    repo: RepoListaFalso([
      filaLista('u1', numero: '101'),
      filaLista('u2', numero: '102', metrosAlNorte: 20),
    ]),
    escala: escala,
    masOverrides: [
      idsFueraDelAreaProvider.overrideWith((ref) async* {
        yield iniciales;
        yield* marcas.stream;
      }),
    ],
  );

  ProviderContainer contenedor(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(_fila('u1')));

  testWidgets('la fila fuera del área lleva la etiqueta y el lector lo dice; la otra no', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await montar(tester, {'u1'});

    expect(_etiquetaEn('u1'), findsOneWidget);
    expect(_etiquetaEn('u2'), findsNothing);
    expect(
      find.descendant(of: _fila('u1'), matching: find.text('FUERA DE TU ÁREA')),
      findsOneWidget,
    );
    expect(tester.getSemantics(_fila('u1')).label, contains('Fuera de tu área'));
    expect(tester.getSemantics(_fila('u2')).label, isNot(contains('Fuera de tu área')));
    semantica.dispose();
  });

  testWidgets('ocultar en el mapa no oculta nada en la Lista: la fila sigue, con su etiqueta', (
    tester,
  ) async {
    await montar(tester, {'u1'});

    contenedor(tester).read(verFueraDelAreaProvider.notifier).ocultar();
    await asentarLista(tester);

    expect(_fila('u1'), findsOneWidget);
    expect(_fila('u2'), findsOneWidget);
    expect(_etiquetaEn('u1'), findsOneWidget);
  });

  testWidgets('el pull saca una casa del área y la devuelve: la etiqueta aparece y se va', (
    tester,
  ) async {
    await montar(tester, const {});
    expect(_etiquetaEn('u2'), findsNothing);

    marcas.add({'u2'});
    await asentarLista(tester);
    expect(_etiquetaEn('u2'), findsOneWidget);

    marcas.add(const {});
    await asentarLista(tester);
    expect(_etiquetaEn('u2'), findsNothing);
  });

  testWidgets('texto al 200 %: la fila con la etiqueta no desborda', (tester) async {
    await montar(tester, {'u1', 'u2'}, escala: 2);

    expect(_etiquetaEn('u1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la hoja de la casa abierta desde la fila marcada lleva la misma etiqueta (decisión '
      'del 17/11, P1 del QA de #718)', (tester) async {
    await montar(tester, {'u1'}, casaAbreSuHoja: true);

    await tester.tap(find.text('Av. Italia 101'));
    await asentarLista(tester, 14);
    // La de la fila y la de la hoja.
    expect(find.byType(EtiquetaFueraDelArea), findsNWidgets(2));
  });

  testWidgets('la hoja de una casa del área abierta desde la Lista no lleva la etiqueta', (
    tester,
  ) async {
    await montar(tester, {'u1'}, casaAbreSuHoja: true);

    await tester.tap(find.text('Av. Italia 102'));
    await asentarLista(tester, 14);
    expect(find.byType(EtiquetaFueraDelArea), findsOneWidget, reason: 'solo la de la fila de u1');
  });
}

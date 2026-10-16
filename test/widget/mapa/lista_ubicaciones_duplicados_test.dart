// El aviso «N posibles duplicados · Revisar» de la Lista (canvas de la vista 10, HU-UBI-006, #208):
// aparece solo si hay pares para revisar, lleva a «Posibles duplicados» y no abre dos pantallas.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/duplicados_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';

final _aviso = find.byKey(const Key('lista_aviso_duplicados'));

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _montar(
  WidgetTester tester, {
  required int pares,
  RepoListaFalso? repo,
  Future<void> Function()? alRevisar,
  double escala = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesLista(repo: repo ?? RepoListaFalso([filaLista('u1'), filaLista('u2')])),
        cantidadParesParaRevisarProvider.overrideWith((ref, colportorId) => pares),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: ListaUbicacionesPage(colportorId: 'col-1', alRevisarDuplicados: alRevisar),
        ),
      ),
    ),
  );
  await _asentar(tester);
}

void main() {
  group('Aviso de posibles duplicados en la Lista', () {
    testWidgets('dado tres pares, se ve "3 posibles duplicados · Revisar" tocable', (tester) async {
      await _montar(tester, pares: 3);

      expect(_aviso, findsOneWidget);
      expect(find.textContaining('3 posibles duplicados', findRichText: true), findsOneWidget);
      expect(find.textContaining('Revisar', findRichText: true), findsOneWidget);
      expect(tester.getSize(_aviso).height, greaterThanOrEqualTo(48));
    });

    testWidgets('dado un solo par, el aviso dice "1 posible duplicado" en singular', (
      tester,
    ) async {
      await _montar(tester, pares: 1);

      expect(find.textContaining('1 posible duplicado', findRichText: true), findsOneWidget);
      expect(find.textContaining('posibles duplicados', findRichText: true), findsNothing);
    });

    testWidgets('dado que no hay pares, no hay aviso ni lugar reservado', (tester) async {
      await _montar(tester, pares: 0);

      expect(_aviso, findsNothing);
    });

    testWidgets('dado que no hay ubicaciones, no hay aviso aunque haya pares', (tester) async {
      await _montar(tester, pares: 2, repo: RepoListaFalso());

      expect(_aviso, findsNothing);
    });

    testWidgets('dado el aviso, un lector de pantalla lo anuncia como botón con su cuenta', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, pares: 3);

      expect(find.bySemanticsLabel('3 posibles duplicados. Revisar'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantica.dispose();
    });

    testWidgets('dado el aviso, cuando lo toco dos veces seguidas, abre "Revisar" una sola vez', (
      tester,
    ) async {
      final abiertas = Completer<void>();
      var veces = 0;
      await _montar(
        tester,
        pares: 3,
        alRevisar: () {
          veces++;
          return abiertas.future;
        },
      );

      await tester.tap(_aviso);
      await tester.tap(_aviso);
      await _asentar(tester);

      expect(veces, 1);

      abiertas.complete();
      await _asentar(tester);
      await tester.tap(_aviso);
      await _asentar(tester);

      expect(veces, 2, reason: 'al volver se puede abrir de nuevo');
    });

    testWidgets('dado el aviso, cuando lo toco, abre "Posibles duplicados"', (tester) async {
      await _montar(tester, pares: 3);

      await tester.tap(_aviso);
      await _asentar(tester);

      expect(find.byType(PosiblesDuplicadosPage), findsOneWidget);
      expect(find.byKey(const Key('duplicados_volver')), findsOneWidget);

      await tester.tap(find.byKey(const Key('duplicados_volver')));
      await _asentar(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(PosiblesDuplicadosPage), findsNothing);
      expect(_aviso, findsOneWidget);
    });

    testWidgets('dado la letra al 200 %, el aviso no se desborda', (tester) async {
      await _montar(tester, pares: 12, escala: 2);

      expect(tester.takeException(), isNull);
      expect(_aviso, findsOneWidget);
    });
  });

  group('La franja es lo primero de lo que se desplaza (QA de #357)', () {
    RepoListaFalso muchas() => RepoListaFalso([for (var i = 0; i < 40; i++) filaLista('u$i')]);

    testWidgets('dado 40 filas, cuando bajo la lista, la franja se va con las filas y al subir '
        'vuelve', (tester) async {
      await _montar(tester, pares: 3, repo: muchas());
      expect(_aviso.hitTestable(), findsOneWidget);
      final arriba = tester.getTopLeft(_aviso).dy;

      await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, -500));
      await _asentar(tester);
      expect(_aviso.hitTestable(), findsNothing, reason: 'se fue con lo que se desplaza');

      await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, 5000));
      await _asentar(tester);
      expect(_aviso.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(_aviso).dy, arriba);
    });

    testWidgets('dado 40 filas, la primera fila está debajo de la franja y la última se alcanza '
        'bajando', (tester) async {
      await _montar(tester, pares: 3, repo: muchas());

      expect(
        tester.getTopLeft(find.byKey(const ValueKey('u0'))).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(_aviso).dy),
      );
      await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, -20000));
      await _asentar(tester);
      expect(find.byKey(const ValueKey('u39')), findsOneWidget);
    });

    testWidgets('dado una búsqueda sin resultados, la franja queda arriba del texto de "Sin '
        'resultados"', (tester) async {
      await _montar(tester, pares: 3);

      await tester.enterText(find.byKey(const Key('lista_busqueda')), 'zzzz');
      await tester.pump(const Duration(milliseconds: 300));
      await _asentar(tester);

      expect(find.text('Sin resultados'), findsOneWidget);
      expect(_aviso, findsOneWidget);
      expect(
        tester.getBottomLeft(_aviso).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('Sin resultados')).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado una búsqueda sin resultados y sin pares, no hay franja y el texto sigue '
        'centrado', (tester) async {
      await _montar(tester, pares: 0);

      await tester.enterText(find.byKey(const Key('lista_busqueda')), 'zzzz');
      await tester.pump(const Duration(milliseconds: 300));
      await _asentar(tester);

      expect(find.text('Sin resultados'), findsOneWidget);
      expect(_aviso, findsNothing);
    });

    testWidgets('dado la franja, el lector de pantalla puede tocarla (acción de toque)', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, pares: 3);

      expect(
        tester.getSemantics(find.bySemanticsLabel('3 posibles duplicados. Revisar')),
        isSemantics(isButton: true, isLiveRegion: true, hasTapAction: true),
      );

      tester.semantics.tap(find.semantics.byLabel('3 posibles duplicados. Revisar'));
      await _asentar(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PosiblesDuplicadosPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('duplicados_volver')));
      await _asentar(tester);
      await tester.pump(const Duration(seconds: 1));
      semantica.dispose();
    });
  });
}

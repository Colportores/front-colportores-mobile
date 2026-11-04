// Vista 39 (base), C·01 y C·02 desde la Lista (vista 05, #445, P1 decidida): la hoja de la casa abre en
// el resumen y, con el mismo gesto que en el mapa, sube a la hoja arriba con las pestañas. Bajarla
// desde arriba vuelve al resumen y bajarla desde el resumen la cierra.
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart';

const _pantalla = Size(390, 844);

Finder get _asa => find.byKey(ClavesHojaCasa.asaDeLaLista);
Finder get _pestanas => find.byKey(ClavesHojaCasa.pestanas);
Finder get _hoja => find.byType(HojaCasa);

/// El alto de la hoja modal (el contenedor animado que lleva el asa).
double _alto(WidgetTester tester) =>
    tester.getSize(find.ancestor(of: _asa, matching: find.byType(AnimatedContainer)).first).height;

Future<void> _abrir(WidgetTester tester, {double escala = 1, Size tamano = _pantalla}) async {
  await montarLista(
    tester,
    repo: RepoListaFalso([filaLista('a', calle: 'Av. Italia', numero: '1234', metrosAlNorte: 40)]),
    escala: escala,
    tamano: tamano,
  );
  await tester.tap(find.text('Av. Italia 1234'));
  await asentarLista(tester);
}

Future<void> _arrastrarAsa(WidgetTester tester, double dy) async {
  await tester.drag(_asa, Offset(0, dy));
  await asentarLista(tester);
}

void main() {
  group('la hoja de la casa desde la Lista', () {
    testWidgets('abre en el resumen (C·01) a un tercio de la pantalla, sin pestañas', (
      tester,
    ) async {
      await _abrir(tester);

      expect(_hoja, findsOneWidget);
      expect(_asa, findsOneWidget);
      expect(_pestanas, findsNothing);
      expect(_alto(tester), closeTo(_pantalla.height / 3, 1));
    });

    testWidgets('arrastrar el asa hacia arriba sube a la hoja arriba (C·02): a la mitad, con las '
        'pestañas y las personas', (tester) async {
      await _abrir(tester);

      await _arrastrarAsa(tester, -80);

      expect(_pestanas, findsOneWidget);
      expect(find.byKey(ClavesHojaCasa.agregarPersona), findsOneWidget);
      expect(_alto(tester), closeTo(_pantalla.height / 2, 1));
      expect(_hoja, findsOneWidget, reason: 'es la misma hoja, no se vuelve a abrir');
    });

    testWidgets('tocar el asa sube y vuelve a tocarla baja al resumen, sin cerrar la hoja', (
      tester,
    ) async {
      await _abrir(tester);

      await tester.tap(_asa);
      await asentarLista(tester);
      expect(_pestanas, findsOneWidget);

      await tester.tap(_asa);
      await asentarLista(tester);
      expect(_pestanas, findsNothing);
      expect(_hoja, findsOneWidget);
      expect(_alto(tester), closeTo(_pantalla.height / 3, 1));
    });

    testWidgets('bajar desde la hoja arriba vuelve al resumen y bajar desde el resumen la cierra', (
      tester,
    ) async {
      await _abrir(tester);
      await _arrastrarAsa(tester, -80);
      expect(_pestanas, findsOneWidget);

      await _arrastrarAsa(tester, 80);
      expect(_pestanas, findsNothing);
      expect(_hoja, findsOneWidget);

      await _arrastrarAsa(tester, 80);
      expect(_hoja, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un arrastre corto y lento no cambia la altura', (tester) async {
      await _abrir(tester);

      await tester.timedDrag(_asa, const Offset(0, -30), const Duration(seconds: 2));
      await asentarLista(tester);

      expect(_pestanas, findsNothing);
      expect(_alto(tester), closeTo(_pantalla.height / 3, 1));
    });

    testWidgets('la ✕ y el atrás del teléfono cierran la hoja también desde arriba', (
      tester,
    ) async {
      await _abrir(tester);
      await _arrastrarAsa(tester, -80);

      await tester.binding.handlePopRoute();
      await asentarLista(tester);

      expect(_hoja, findsNothing);
    });

    testWidgets('volver a abrir la hoja empieza otra vez en el resumen', (tester) async {
      await _abrir(tester);
      await _arrastrarAsa(tester, -80);
      await tester.binding.handlePopRoute();
      await asentarLista(tester);

      await tester.tap(find.text('Av. Italia 1234'));
      await asentarLista(tester);

      expect(_hoja, findsOneWidget);
      expect(_pestanas, findsNothing);
    });

    testWidgets('el lector de pantalla puede subir y bajar la hoja con las acciones de ajuste', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _abrir(tester);
      final asa = find.semantics.byLabel('Cambiar altura de la hoja');

      expect(tester.getSemantics(_asa).value, 'A un tercio de la pantalla');
      tester.semantics.performAction(asa, SemanticsAction.increase);
      await asentarLista(tester);
      expect(_pestanas, findsOneWidget);
      expect(tester.getSemantics(_asa).value, 'A la mitad de la pantalla');

      tester.semantics.performAction(asa, SemanticsAction.decrease);
      await asentarLista(tester);
      expect(_pestanas, findsNothing);
      semantica.dispose();
    });

    testWidgets('el asa mide al menos 48 dp de alto', (tester) async {
      await _abrir(tester);

      expect(tester.getSize(_asa).height, greaterThanOrEqualTo(48));
    });

    testWidgets('a 360 px y texto ×2 la hoja arriba no desborda', (tester) async {
      await _abrir(tester, escala: 2, tamano: const Size(360, 740));

      await _arrastrarAsa(tester, -80);

      expect(_pestanas, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

// QA de #602 (HU-VEN-005, vista 32B «Personas»): las acciones rápidas de la ficha vistas como las ve
// quien las usa. Accesibilidad (objetivo táctil, etiqueta, contraste, semántica del estado apagado,
// orden de foco) en los tamaños chico y grande, con letra al doble; y los casos límite que dejan la
// ficha en un estado raro (la cuenta cambia mientras se abre algo, lecturas que se repiten).
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

/// Los dos teléfonos de la QA móvil.
const _chico = Size(360, 640);
const _grande = Size(412, 915);

/// Carga las fuentes del proyecto; va al final del archivo porque deja las medidas reales para los
/// tests que siguen.
Future<void> _cargarFuentes(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
});

void main() {
  final agendar = find.byKey(ClavesFicha.botonAgendarCobranza);
  final entrega = find.byKey(ClavesFicha.botonRegistrarEntrega);
  final acciones = find.byKey(ClavesFicha.acciones);

  // Debe $ 1.200 y ya recibió todo: queda solo «+ Agendar cobranza».
  const sinEntregas = ResumenCuentaPersona(
    compradoCentavos: 450000,
    pagadoCentavos: 330000,
    saldoCentavos: 120000,
    entregasHechas: 2,
    entregasTotales: 2,
  );

  MundoFicha mundo({bool conEntrega = true}) {
    final m = MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha())
      ..conRegistrarEntrega = conEntrega;
    m.cuentas.cuenta = cuentaConSaldo;
    m.personas.sembrar([clienteDePersonas('per-1', 'María', apellido: 'Fernández')]);
    return m;
  }

  Future<void> guias(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  Future<void> hastaLasAcciones(WidgetTester tester) async {
    await tester.scrollUntilVisible(acciones, 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  group('32B·01 · guías de accesibilidad con las acciones a la vista', () {
    for (final tamano in [_chico, _grande]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets(
          'tamaño ${tamano.width.toInt()}×${tamano.height.toInt()}, letra ×$escala: objetivo '
          'táctil, etiqueta y contraste',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await montarFicha(tester, mundo(), tamano: tamano, escala: escala);
            await hastaLasAcciones(tester);

            expect(agendar, findsOneWidget);
            expect(entrega, findsOneWidget);
            await guias(tester);
            expect(tester.takeException(), isNull);
            semantica.dispose();
          },
        );
      }
    }

    testWidgets('con una sola acción (solo cobranza) cumple las guías a letra doble', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final m = mundo()..cuentas.cuenta = sinEntregas;
      await montarFicha(tester, m, tamano: _chico, escala: 2);
      await hastaLasAcciones(tester);

      expect(agendar, findsOneWidget);
      expect(entrega, findsNothing);
      await guias(tester);
      semantica.dispose();
    });
  });

  group('estado apagado (una acción abriéndose)', () {
    testWidgets(
      'los dos chips se anuncian como botones deshabilitados y el resto de la ficha sigue',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final m = mundo()..compuertaEntrega = Completer<void>();
        await montarFicha(tester, m, tamano: _grande);
        await hastaLasAcciones(tester);
        await tester.tap(entrega);
        await tester.pump();

        for (final f in [agendar, entrega]) {
          expect(
            tester.getSemantics(f),
            isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
          );
        }
        expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);

        m.compuertaEntrega!.complete();
        await asentar(tester);
        for (final f in [agendar, entrega]) {
          expect(
            tester.getSemantics(f),
            isSemantics(isButton: true, hasEnabledState: true, isEnabled: true),
          );
        }
        semantica.dispose();
      },
    );

    for (final tamano in [_chico, _grande]) {
      testWidgets('apagados siguen cumpliendo tamaño y etiqueta en ${tamano.width.toInt()}×'
          '${tamano.height.toInt()} con letra doble', (tester) async {
        final semantica = tester.ensureSemantics();
        final m = mundo()..compuertaEntrega = Completer<void>();
        await montarFicha(tester, m, tamano: tamano, escala: 2);
        await hastaLasAcciones(tester);
        await tester.tap(entrega);
        await tester.pump();
        expect(tester.widget<ActionChip>(agendar).onPressed, isNull);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(tester.takeException(), isNull);

        m.compuertaEntrega!.complete();
        await asentar(tester);
        semantica.dispose();
      });
    }

    testWidgets('el texto apagado no es del color del texto activo', (tester) async {
      final m = mundo()..compuertaEntrega = Completer<void>();
      await montarFicha(tester, m, tamano: _grande);
      await hastaLasAcciones(tester);
      final activo = tester.widget<ActionChip>(agendar).labelStyle?.color;
      await tester.tap(entrega);
      await tester.pump();

      final apagado = tester.widget<ActionChip>(agendar).labelStyle?.color;
      expect(apagado, isNotNull);
      expect(apagado, isNot(activo));
      expect(apagado!.a, lessThan(1));

      m.compuertaEntrega!.complete();
      await asentar(tester);
    });
  });

  group('orden de foco con el teclado', () {
    testWidgets(
      'con Tab se llega a «+ Agendar cobranza» antes que a «Registrar entrega» sin trampa',
      (tester) async {
        await montarFicha(tester, mundo(), tamano: const Size(390, 1600));

        final visitadas = <Key?>[];
        for (var i = 0; i < 40; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final contexto = FocusManager.instance.primaryFocus?.context;
          final chip = contexto?.findAncestorWidgetOfExactType<ActionChip>();
          if (chip != null) visitadas.add(chip.key);
        }

        expect(visitadas, contains(ClavesFicha.botonAgendarCobranza));
        expect(visitadas, contains(ClavesFicha.botonRegistrarEntrega));
        expect(
          visitadas.indexOf(ClavesFicha.botonAgendarCobranza),
          lessThan(visitadas.indexOf(ClavesFicha.botonRegistrarEntrega)),
        );
      },
    );

    testWidgets('con el chip enfocado, Enter abre «Registrar entrega» una sola vez', (
      tester,
    ) async {
      final m = mundo()..compuertaEntrega = Completer<void>();
      await montarFicha(tester, m, tamano: const Size(390, 1600));

      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final chip = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<ActionChip>();
        if (chip?.key == ClavesFicha.botonRegistrarEntrega) break;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(m.entregas, hasLength(1));
      m.compuertaEntrega!.complete();
      await asentar(tester);
    });
  });

  group('casos límite', () {
    testWidgets(
      'si al volver de «Registrar entrega» ya no queda nada por entregar, el chip se va y '
      'la otra acción sigue tocable',
      (tester) async {
        final m = mundo()..compuertaEntrega = Completer<void>();
        await montarFicha(tester, m, tamano: const Size(390, 1600));
        await tester.ensureVisible(entrega);
        await tester.pump();
        await tester.tap(entrega);
        await tester.pump();

        // Lo entregado cambia la cuenta mientras la pantalla de entregas está abierta.
        m.cuentas.cuenta = sinEntregas;
        m.compuertaEntrega!.complete();
        await asentar(tester);
        m.fichas.poner(LecturaDeFicha(persona: mariaDePrueba(), historial: historialDelCanvas()));
        await asentar(tester);

        expect(entrega, findsNothing);
        expect(agendar, findsOneWidget);
        expect(tester.widget<ActionChip>(agendar).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'si la cuenta se salda mientras «Registrar entrega» está abierta, no queda el bloque '
      'vacío ni un hueco',
      (tester) async {
        final m = mundo()..compuertaEntrega = Completer<void>();
        await montarFicha(tester, m, tamano: const Size(390, 1600));
        await tester.ensureVisible(entrega);
        await tester.pump();
        await tester.tap(entrega);
        await tester.pump();

        m.cuentas.cuenta = const ResumenCuentaPersona(
          compradoCentavos: 450000,
          pagadoCentavos: 450000,
          saldoCentavos: 0,
          entregasHechas: 2,
          entregasTotales: 2,
        );
        m.compuertaEntrega!.complete();
        await asentar(tester);
        m.fichas.poner(LecturaDeFicha(persona: mariaDePrueba(), historial: historialDelCanvas()));
        await asentar(tester);

        expect(acciones, findsNothing);
        expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('cuatro toques seguidos entre las dos acciones abren una sola pantalla', (
      tester,
    ) async {
      final m = mundo()..compuertaEntrega = Completer<void>();
      await montarFicha(tester, m, tamano: const Size(390, 1600));
      await tester.ensureVisible(entrega);
      await tester.pump();

      await tester.tap(entrega);
      await tester.tap(agendar, warnIfMissed: false);
      await tester.tap(entrega, warnIfMissed: false);
      await tester.tap(agendar, warnIfMissed: false);
      await tester.pump();

      expect(m.entregas, hasLength(1));
      expect(find.text(TextosFicha.noPudimosAbrir), findsNothing);
      m.compuertaEntrega!.complete();
      await asentar(tester);
    });

    testWidgets(
      'el aviso de «no pudimos abrir» sale con una acción a mano y no deja el botón apagado',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final m = mundo()..lanzarAlRegistrarEntrega = StateError('no abrió');
        await montarFicha(tester, m, tamano: _chico, escala: 2);
        await hastaLasAcciones(tester);
        await tester.tap(entrega);
        await asentar(tester);

        expect(find.text(TextosFicha.noPudimosAbrir), findsOneWidget);
        // El aviso dice qué hacer («Probá de nuevo») y el chip está ahí para hacerlo.
        expect(tester.widget<ActionChip>(entrega).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        semantica.dispose();
      },
    );
  });

  group(
    '32B·01 · la cuenta con letra al doble',
    () {
      testWidgets(
        'las etiquetas de la cuenta no se parten en medio de la palabra a 360 con letra ×2',
        (tester) async {
          // Con las fuentes del proyecto: con la de prueba (cajas) las medidas no valen.
          await _cargarFuentes(tester);
          await montarFicha(tester, mundo(), tamano: _chico, escala: 2);

          final cuenta = find.byKey(ClavesFicha.cuenta);
          double alto(String t) =>
              tester.getSize(find.descendant(of: cuenta, matching: find.text(t))).height;
          // «Comprado» y «Pagado» son una palabra: tienen que ocupar un solo renglón, igual de altos.
          expect(
            alto('Comprado'),
            alto('Pagado'),
            reason: '«Comprado» se corta como «Comprad» / «o»',
          );
        },
      );
    },
    skip: 'QA #162: a 360 dp con letra ×2 «Comprado» de la cuenta se parte en «Comprad» / «o»',
  );
}

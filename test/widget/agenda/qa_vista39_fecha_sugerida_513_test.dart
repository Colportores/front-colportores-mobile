// QA de la vista 39 R·02 y R·03 en «Agendar visita» (#513). Complementa los tests del implementador con:
//   - la matriz de estados × 360x640/412x915 × texto 1,0/2,0 (sin overflow, sin texto cortado);
//   - el lector de pantalla (tarjeta, interruptor, hora acordada);
//   - casos límite: lectura que llega tarde (con otro tipo, con la estricta, con un guardado en curso),
//     falla a mitad del guardado con la sugerencia, muchas entrevistas, día cambiado en la estricta;
//   - hallazgos con `skip` (`--dart-define=QA_HALLAZGOS=true` los corre).
// Las capturas solo con `--dart-define=QA_CAPTURAS=true` (`.dart_tool/qa_capturas/513_*.png`).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/entrevista_cercana.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/sugerencia_de_fecha.dart';
import 'package:colportores_mobile/features/agenda/domain/services/sugeridor_de_fecha.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/qa_vista39_513_arnes.dart';

String _sufijo(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

bool _prendido(WidgetTester tester) => tester.widget<SwitchListTile>(interruptor513).value;

void main() {
  usarFuentesReales408 = true;

  group('matriz de estados · sin overflow ni texto cortado', () {
    for (final tamano in [chico, grande]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado513.values) {
          testWidgets('${estado.rotulo} · ${_sufijo(tamano, escala)}', (tester) async {
            await llegarA513(tester, estado, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull, reason: 'overflow en ${estado.rotulo}');
            sinTextoCortado408(tester);
            await capturar513(tester, '${estado.name}_${_sufijo(tamano, escala)}');
            // El botón de agendar sigue alcanzable (con el scroll) salvo bajo una hoja.
            final hayHoja = find.byType(BottomSheet).evaluate().isNotEmpty;
            final hayDialogo = find.byType(Dialog).evaluate().isNotEmpty;
            if (!hayHoja && !hayDialogo) {
              if (tarjeta513.evaluate().isNotEmpty) {
                await tester.ensureVisible(tarjeta513);
                await tester.pump();
                await capturar513(tester, '${estado.name}_${_sufijo(tamano, escala)}_tarjeta');
              }
              await tester.ensureVisible(boton513);
              await tester.pump();
              expect(tester.takeException(), isNull);
            }
          });
        }
      }
    }
  });

  group('texto literal del canvas (R·02 y R·03)', () {
    testWidgets(
      'R·02: SUGERIDA, el día con la franja, cuántas hay, Cambiar y el interruptor con su ayuda',
      (tester) async {
        await montar513(tester);
        expect(find.text('SUGERIDA'), findsOneWidget);
        expect(find.text('Lunes 26/10 · 16:30 a 18:00'), findsOneWidget);
        expect(find.text('2 entrevistas a menos de 300 m ese día'), findsOneWidget);
        expect(find.text('Cambiar'), findsOneWidget);
        expect(find.text('Entrevista estricta'), findsOneWidget);
        expect(find.text('Hora fija acordada con la persona'), findsOneWidget);
        expect(_prendido(tester), isFalse);
        // Las seis franjas de §8.5.2, la sugerida elegida.
        for (final f in FranjaHoraria.values) {
          expect(find.text(f.etiqueta), findsOneWidget);
        }
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.primeraTarde)),
              )
              .selected,
          isTrue,
        );
      },
    );

    testWidgets('R·03: FECHA solo con el día, sin franjas, y HORA ACORDADA con la hora', (
      tester,
    ) async {
      await montar513(tester);
      await tocar513(tester, interruptor513);
      expect(_prendido(tester), isTrue);
      expect(find.text('FECHA'), findsOneWidget);
      expect(find.text('Lunes 26/10'), findsOneWidget);
      expect(find.text('SUGERIDA'), findsNothing);
      expect(find.text('HORA ACORDADA'), findsOneWidget);
      expect(find.text('16:30'), findsOneWidget);
      for (final f in FranjaHoraria.values) {
        expect(find.byKey(ClavesAgendarVisita.franja(f)), findsNothing);
      }
    });
  });

  group('tamaño real de lo tocable nuevo', () {
    for (final tamano in [chico, grande]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets(
          'la tarjeta, el interruptor y la hora acordada miden 48 dp o más · ${_sufijo(tamano, escala)}',
          (tester) async {
            await montar513(tester, tamano: tamano, escala: escala);
            await tester.ensureVisible(tarjeta513);
            expect(tester.getSize(tarjeta513).height, greaterThanOrEqualTo(48));
            await tester.ensureVisible(interruptor513);
            expect(tester.getSize(interruptor513).height, greaterThanOrEqualTo(48));
            await tocar513(tester, interruptor513);
            await tester.ensureVisible(tarjeta513);
            expect(tester.getSize(tarjeta513).height, greaterThanOrEqualTo(48));
            expect(tester.getSize(tarjeta513).width, greaterThanOrEqualTo(48));
            await tester.ensureVisible(horaAcordada513);
            expect(tester.getSize(horaAcordada513).height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('lector de pantalla', () {
    testWidgets('la tarjeta SUGERIDA se lee entera, es un botón y tiene acción de tocar', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await montar513(tester);
      final s = tester.getSemantics(tarjeta513);
      expect(
        s.label,
        'Fecha sugerida: Lunes 26/10 · 16:30 a 18:00. 2 entrevistas a menos de 300 m ese día. '
        'Tocá para cambiar',
      );
      expect(s, isSemantics(isButton: true, hasTapAction: true));
      h.dispose();
    });

    testWidgets(
      'el interruptor dice su nombre y su estado, y la hora acordada se lee con la hora',
      (tester) async {
        final h = tester.ensureSemantics();
        await montar513(tester);
        var s = tester.getSemantics(interruptor513);
        expect(s.label, contains('Entrevista estricta'));
        expect(s.label, contains('Hora fija acordada con la persona'));
        expect(s, isSemantics(hasToggledState: true, isToggled: false, hasTapAction: true));
        await tocar513(tester, interruptor513);
        s = tester.getSemantics(interruptor513);
        expect(s, isSemantics(hasToggledState: true, isToggled: true, hasTapAction: true));
        final hora = tester.getSemantics(horaAcordada513);
        expect(hora.label, 'Hora acordada: 16:30. Tocá para cambiar');
        expect(hora, isSemantics(isButton: true, hasTapAction: true));
        h.dispose();
      },
    );

    testWidgets('con la hora acordada que ya pasó, el aviso se anuncia (región viva)', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarA513(tester, Estado513.r03HoraPasada);
      final error = find.byKey(ClavesAgendarVisita.errorHoraAcordada);
      expect(error, findsOneWidget);
      expect(find.text('Esa hora ya pasó'), findsOneWidget);
      final vivo = find.ancestor(
        of: error,
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      );
      expect(vivo, findsWidgets);
      h.dispose();
    });
  });

  group('casos límite · la lectura llega tarde', () {
    testWidgets(
      'dada una lectura lenta, cuando se pasa a Cobranza y llega, entonces no se sugiere; al volver a Entrevista sí',
      (tester) async {
        final compuerta = Completer<void>();
        await montar513(
          tester,
          lectura: EntrevistasCercanasFalsas(dosEnLaTarde513(), compuerta: compuerta),
        );
        await tocar513(tester, find.text('Cobranza'));
        compuerta.complete();
        await asentarAgendar(tester);
        expect(tarjeta513, findsNothing);
        expect(interruptor513, findsNothing);
        expect(find.text('Mañana · 10:00'), findsOneWidget);
        await tocar513(tester, find.text('Entrevista'));
        expect(find.text('SUGERIDA'), findsOneWidget);
        expect(find.text('Lunes 26/10 · 16:30 a 18:00'), findsOneWidget);
      },
    );

    testWidgets(
      'dada una lectura lenta, cuando ya se prendió la estricta y llega, entonces no le pisa el día ni la hora',
      (tester) async {
        final compuerta = Completer<void>();
        final x = await montar513(
          tester,
          lectura: EntrevistasCercanasFalsas(dosEnLaTarde513(), compuerta: compuerta),
        );
        await tocar513(tester, interruptor513);
        expect(find.text('Sábado 24/10'), findsOneWidget);
        compuerta.complete();
        await asentarAgendar(tester);
        expect(find.text('FECHA'), findsOneWidget);
        expect(find.text('Sábado 24/10'), findsOneWidget);
        expect(find.text('10:00'), findsOneWidget);
        await tocar513(tester, boton513);
        final a = x.repo.recibidas.single.agenda;
        expect(a.fechaProgramada, DateTime(2026, 10, 24, 10).toUtc());
        expect(a.esEstricta, isTrue);
        expect(a.slotCodigo, isNull);
      },
    );

    testWidgets(
      'dado un guardado en curso, cuando llega la lectura, entonces el formulario no cambia de fecha y el guardado sale con la fecha que tenía',
      (tester) async {
        final compuerta = Completer<void>();
        final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
        final x = await montar513(
          tester,
          lectura: EntrevistasCercanasFalsas(dosEnLaTarde513(), compuerta: compuerta),
          repo: repo,
        );
        await tester.tap(boton513);
        await tester.pump(const Duration(milliseconds: 50));
        compuerta.complete();
        await asentarAgendar(tester);
        expect(tarjeta513, findsNothing);
        repo.compuerta!.complete();
        await asentarAgendar(tester);
        final a = x.repo.recibidas.single.agenda;
        expect(a.fechaProgramada, DateTime(2026, 10, 24, 10).toUtc());
        expect(a.slotCodigo, 'mid_morning');
        expect(x.arnes.resultados, [true]);
      },
    );
  });

  group('casos límite · guardar y reintentar con la sugerencia', () {
    testWidgets(
      'dada la sugerencia, cuando el guardado falla a mitad, entonces el botón vuelve a «Reintentar», la tarjeta se conserva y el reintento usa los mismos ids',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..fallas.add(const FailureInesperado());
        final x = await montar513(tester, repo: repo);
        await tocar513(tester, boton513);
        expect(find.byKey(ClavesAgendarVisita.avisoFalla), findsOneWidget);
        expect(find.text('Reintentar'), findsWidgets);
        expect(find.text('SUGERIDA'), findsOneWidget);
        expect(find.text('Lunes 26/10 · 16:30 a 18:00'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(of: boton513, matching: find.byType(FilledButton)),
              )
              .onPressed,
          isNotNull,
        );
        await tocar513(tester, boton513);
        expect(x.arnes.resultados, [true]);
        final ids = x.repo.recibidas.map((r) => r.agenda.id).toSet();
        expect(ids, hasLength(1), reason: 'el reintento no crea otra agenda');
        expect(x.repo.recibidas.last.agenda.slotCodigo, 'early_afternoon');
      },
    );

    testWidgets(
      'dado un guardado en curso, cuando se toca la tarjeta de la fecha, entonces no abre la hoja',
      (tester) async {
        await llegarA513(tester, Estado513.r03Agendando);
        await tester.tap(tarjeta513, warnIfMissed: false);
        await asentarAgendar(tester);
        expect(find.byKey(ClavesAgendarVisita.hojaListo), findsNothing);
        await tester.tap(horaAcordada513, warnIfMissed: false);
        await asentarAgendar(tester);
        expect(find.byType(TimePickerDialog), findsNothing);
      },
    );

    testWidgets(
      'dada la estricta, cuando se cambia solo el día con Cambiar, entonces la hora acordada se conserva',
      (tester) async {
        final x = await montar513(tester);
        await tocar513(tester, interruptor513);
        await tocar513(tester, tarjeta513);
        await tocar513(tester, find.byKey(ClavesAgendarVisita.dia(2)));
        await tocar513(tester, find.byKey(ClavesAgendarVisita.hojaListo));
        expect(find.text('16:30'), findsOneWidget);
        expect(find.text('Lunes 26/10'), findsNothing);
        expect(find.text('Domingo 25/10'), findsOneWidget);
        await tocar513(tester, boton513);
        final a = x.repo.recibidas.single.agenda;
        expect(a.fechaProgramada.toLocal().hour, 16);
        expect(a.fechaProgramada.toLocal().minute, 30);
        expect(a.fechaProgramada.toLocal().day, 25);
        expect(a.esEstricta, isTrue);
      },
    );

    testWidgets(
      'con una nota larga y la estricta prendida, se guarda la nota entera sin trabar nada',
      (tester) async {
        final x = await montar513(tester);
        await tocar513(tester, interruptor513);
        final nota = find.byType(TextField).last;
        await tester.ensureVisible(nota);
        await tester.enterText(nota, '😀 ' * 400);
        await tester.pump();
        await tocar513(tester, boton513);
        expect(x.arnes.resultados, [true]);
        expect(x.repo.recibidas.single.agenda.esEstricta, isTrue);
      },
    );
  });

  group('datos límite', () {
    testWidgets('con 120 entrevistas el día es el más largo y la cuenta entra en la tarjeta', (
      tester,
    ) async {
      await montar513(tester, cercanas: muchas513(120));
      expect(find.text('120 entrevistas a menos de 300 m ese día'), findsOneWidget);
      expect(find.textContaining('Miércoles 28/10 · 19:15 a 20:30'), findsOneWidget);
    });

    test(
      'la hora de la sugerencia nunca queda antes de ahora (un día con la franja ya empezada)',
      () {
        // Caracterización: hoy 17:05, dos entrevistas a las 17:30 y 17:45 («Primera tarde», que empezó
        // 16:30): el día se descarta entero aunque todavía queden dos entrevistas por venir.
        final r = SugeridorDeFecha.calcular([
          EntrevistaCercana(fecha: DateTime(2026, 10, 23, 17, 30)),
          EntrevistaCercana(fecha: DateTime(2026, 10, 23, 17, 45)),
          EntrevistaCercana(fecha: DateTime(2026, 10, 27, 10, 30)),
        ], ahora: DateTime(2026, 10, 23, 17, 5));
        expect(r?.momento, DateTime(2026, 10, 27, 10));
        expect(r?.cantidad, 1);
      },
    );

    test('ninguna entrevista cae en franja (de noche): la hora es la de la más temprana', () {
      final r = SugeridorDeFecha.calcular([
        EntrevistaCercana(fecha: DateTime(2026, 10, 27, 21, 15)),
        EntrevistaCercana(fecha: DateTime(2026, 10, 27, 22, 0)),
      ], ahora: DateTime(2026, 10, 23, 14, 35));
      expect(r?.momento, DateTime(2026, 10, 27, 21, 15));
      expect(r?.franja, isNull);
      expect(r?.cantidad, 2);
    });
  });

  group('privacidad', () {
    test('SugerenciaDeFecha y EntrevistaCercana no imprimen sus datos en toString', () {
      final s = SugerenciaDeFecha(momento: DateTime(2026, 10, 26, 16, 30), cantidad: 2);
      final e = EntrevistaCercana(
        fecha: DateTime(2026, 10, 26, 16, 45),
        slotCodigo: 'early_afternoon',
      );
      expect(s.toString(), isNot(contains('2026')));
      expect(e.toString(), isNot(contains('2026')));
      expect(e.toString(), isNot(contains('early_afternoon')));
    });
  });

  group('hallazgos', () {
    // skip: issue #513 — a 360×640 con texto 2,0 la tarjeta SUGERIDA/FECHA parte «Miércoles» en
    // «Miércol/es» (el «Cambiar» y el ícono le dejan ~112 dp a la columna del día).
    for (final estricta in [false, true]) {
      testWidgets('con texto 2,0 en 360×640, ninguna palabra del día se parte en la tarjeta '
          '${estricta ? 'FECHA' : 'SUGERIDA'}', (tester) async {
        final partidas = <String>[];
        for (var dia = 24; dia <= 30; dia++) {
          await montar513(
            tester,
            cercanas: [EntrevistaCercana(fecha: DateTime(2026, 10, dia, 17))],
            escala: 2,
          );
          if (estricta) await tocar513(tester, interruptor513);
          final titulo = find.descendant(of: tarjeta513, matching: find.textContaining('/10'));
          await tester.ensureVisible(titulo);
          final p = tester.renderObject<RenderParagraph>(titulo);
          for (final palabra in p.text.toPlainText().split(' ')) {
            final medida = TextPainter(
              text: TextSpan(text: palabra, style: p.text.style),
              textDirection: TextDirection.ltr,
              textScaler: p.textScaler,
            )..layout();
            if (medida.width > p.size.width + 0.5) partidas.add('$palabra (día $dia)');
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        }
        expect(partidas, isEmpty, reason: 'palabras partidas: $partidas');
      }, skip: !conHallazgos513);
    }
    // skip: issue #513 — P5 (decisión 03/11): si la lectura de las entrevistas cercanas falla, tiene
    // que dejar un log sin PII; hoy la falla se descarta sin dejar rastro.
    testWidgets(
      'dada una falla al leer las entrevistas cercanas, cuando se abre, entonces queda un log sin PII',
      (tester) async {
        final lineas = <String>[];
        void oyente(OutputEvent e) => lineas.addAll(e.lines);
        Logger.addOutputListener(oyente);
        addTearDown(() => Logger.removeOutputListener(oyente));
        await montar513(
          tester,
          lectura: EntrevistasCercanasFalsas(
            const [],
            falla: StateError('sin base de Grecia 3307'),
          ),
        );
        expect(lineas.where((l) => l.contains('AGENDA') || l.contains('agenda')), isNotEmpty);
        expect(lineas.join('\n'), isNot(contains('Grecia')));
      },
      skip: !conHallazgos513,
    );

    // skip: issue #513 — con la estricta, «Cambiar la hora» de la hoja «Esa hora ya pasó» abre la hoja
    // «Día», que no tiene la hora: la acción promete algo que la hoja no hace.
    testWidgets(
      'dada la estricta con la hora pasada, cuando se toca «Cambiar la hora», entonces se puede cambiar la hora',
      (tester) async {
        await llegarA513(tester, Estado513.r03Pregunta);
        await tocar513(tester, find.byKey(ClavesAgendarVisita.horaPasadaCambiar));
        final puedeCambiarLaHora =
            find.byKey(ClavesAgendarVisita.hojaHora).evaluate().isNotEmpty ||
            find.byType(TimePickerDialog).evaluate().isNotEmpty;
        expect(puedeCambiarLaHora, isTrue);
      },
      skip: !conHallazgos513,
    );
  });
}

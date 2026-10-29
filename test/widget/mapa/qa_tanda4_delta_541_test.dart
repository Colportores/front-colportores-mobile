// QA del PR #573 (#541, tanda 4 de los tests saltados): lo que los tests del implementador no miden de
// los siete arreglos. Fronteras de la distancia (#448), reentrada y falla de la lectura previa del paso
// «¿Con quién?» (#449), «Restaurar» de las notas borradas con todas las escalas de texto y tamaños de
// pantalla (#144), cuadro de la cuenta de la baja con valores anchos (#143) y las iniciales del avatar
// que no escalan (#444/#445). `--dart-define=QA_CAPTURAS=true` saca PNG a `.dart_tool/qa_capturas/`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_persona_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista32e_144_arnes.dart';
import '../../helpers/qa_vista39_445_arnes.dart' hide t320x568, t360x640, t412x915;
import '../../helpers/qa_vista39_449_arnes.dart';
import 'hoja_con_quien_arnes.dart';
import 'notas_persona_arnes.dart';
import 'personas_arnes.dart' show montarClientes;
import 'qa_vista32d_baja_143_arnes.dart' as baja;

/// Lee de un repositorio que falla las primeras [fallas] veces.
final class _PersonasQueFallan extends PersonaRepositorioFalso {
  _PersonasQueFallan(this.fallas);

  int fallas;

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) {
    if (fallas > 0) {
      fallas -= 1;
      return Stream.error(StateError('no se pudo leer'));
    }
    return super.observarDelEspacio(espacioId);
  }
}

/// La lista es perezosa: sube hasta el principio y baja hasta que la tarjeta existe y se ve.
Future<void> _traer(WidgetTester tester, Finder f) async {
  final lista = find.byType(Scrollable).first;
  await tester.drag(lista, const Offset(0, 5000));
  await tester.pump();
  for (var i = 0; i < 60 && (f.evaluate().isEmpty || f.hitTestable().evaluate().isEmpty); i++) {
    await tester.drag(lista, const Offset(0, -150));
    await tester.pump();
  }
  expect(f, findsOneWidget);
}

void main() {
  group('#448 · distancia en la frontera del kilómetro', () {
    test(
      'barrido de 0 a 3 km de a 5 cm: nunca «1000 m», nunca baja, el formato es siempre el mismo',
      () {
        const nbsp = FormatoUbicaciones.espacioDuro;
        final metro = RegExp(
          '^\\d{1,3}$nbsp'
          'm\$',
        );
        final kilometro = RegExp(
          '^\\d,\\d$nbsp'
          'km\$',
        );
        var anterior = 0.0;
        for (var m = 0.0; m < 3000; m += 0.05) {
          final t = FormatoUbicaciones.distancia(m);
          expect(t, isNot(contains('1000')), reason: '$m m dice «$t»');
          if (metro.hasMatch(t)) {
            final n = int.parse(t.split(nbsp).first);
            expect(n, inInclusiveRange(1, 999), reason: '$m m dice «$t»');
            expect(n.toDouble(), greaterThanOrEqualTo(anterior - 1e-9), reason: '$m m dice «$t»');
            anterior = n.toDouble();
          } else {
            expect(kilometro.hasMatch(t), isTrue, reason: '$m m dice «$t»');
            expect(m, greaterThanOrEqualTo(999.5), reason: '«$t» antes de 999,5 m');
          }
        }
      },
    );

    test('valores raros: NaN, infinito y negativos son vacío; muy lejos sigue siendo «N,N km»', () {
      expect(FormatoUbicaciones.distancia(double.nan), '');
      expect(FormatoUbicaciones.distancia(double.infinity), '');
      expect(FormatoUbicaciones.distancia(-1), '');
      expect(FormatoUbicaciones.distancia(0), '1 m');
      expect(FormatoUbicaciones.distancia(12345678), '12345,7 km');
    });

    test('el aviso de E·05 usa la misma frontera: «1,0 km», no «1000 m»', () {
      for (final m in [999.5, 999.7, 999.99]) {
        expect(TextosEstadosHojaCasa.lejos(m), 'Estás a 1,0 km de esta casa.');
      }
    });
  });

  group('#449 · lectura previa de «¿Con quién?»', () {
    testWidgets('tres toques seguidos durante la lectura: una sola hoja y una sola apertura', (
      tester,
    ) async {
      final repo = PersonaRepositorioLento(const Duration(milliseconds: 150))
        ..sembrar(personasDeLaCasa(2));
      final r = await montar449(tester, repo: repo, abrir: false);

      await tester.tap(find.text('abrir paso'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('abrir paso'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('abrir paso'));
      await asentar(tester, 20);

      expect(find.byType(HojaConQuien), findsOneWidget);
      expect(r.abiertas, 1);
    });

    testWidgets('cerrar y volver a abrir: la guarda se soltó, abre la hoja otra vez', (
      tester,
    ) async {
      final repo = PersonaRepositorioLento(const Duration(milliseconds: 100))
        ..sembrar(personasDeLaCasa(2));
      final r = await montar449(tester, repo: repo, abrir: false);

      await tester.tap(find.text('abrir paso'));
      await asentar(tester, 20);
      expect(find.byType(HojaConQuien), findsOneWidget);
      await tester.tap(botonVolver449);
      await asentar(tester, 20);
      expect(find.byType(HojaConQuien), findsNothing);

      await tester.tap(find.text('abrir paso'));
      await asentar(tester, 20);
      expect(find.byType(HojaConQuien), findsOneWidget);
      expect(r.abiertas, 1);
    });

    testWidgets(
      'la lectura falla: la hoja abre con «Reintentar» y un toque posterior no queda trabado',
      (tester) async {
        final repo = _PersonasQueFallan(2)..sembrar(personasDeLaCasa(2));
        final r = await montar449(tester, repo: repo, abrir: false);

        await tester.tap(find.text('abrir paso'));
        await asentar(tester, 20);
        expect(find.byType(HojaConQuien), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);

        await tester.tap(botonVolver449);
        await asentar(tester, 20);
        await tester.tap(find.text('abrir paso'));
        await asentar(tester, 20);
        expect(find.byType(HojaConQuien), findsOneWidget);
        expect(r.abiertas, 1);
      },
    );

    testWidgets('lectura que tarda más de 250 ms: sale «cargando» y la guarda ya está suelta', (
      tester,
    ) async {
      final repo = PersonaRepositorioLento(const Duration(seconds: 2))
        ..sembrar(personasDeLaCasa(2));
      final r = await montar449(tester, repo: repo, abrir: false);

      await tester.tap(find.text('abrir paso'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(HojaConQuien), findsOneWidget);
      expect(r.abiertas, 1);
      await tester.tap(botonVolver449);
      await asentar(tester, 20);
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('abrir paso'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      expect(r.abiertas, 1);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('#144 · E·05 «Restaurar» dentro de la tarjeta, a todas las escalas', () {
    final notas = [
      notaDePrueba(
        'b1',
        'Pidió volver el sábado con el esposo.',
        borrada: DateTime(2026, 10, 22, 14, 20),
      ),
      notaDePrueba('b2', List.filled(120, 'palabra').join(' '), borrada: DateTime(2026, 10, 21, 9)),
      notaDePrueba('b3', 'Corta', borrada: DateTime(2026, 9, 5, 9)),
    ];
    const tamanos = [Size(320, 568), Size(360, 640), Size(412, 915)];
    const escalas = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.75, 2.0, 3.0];

    for (final t in tamanos) {
      for (final e in escalas) {
        testWidgets('${t.width.toInt()}×${t.height.toInt()} · $e×: sin overflow, «Restaurar» '
            'dentro de la tarjeta, ≥48 dp, nada fuera de la pantalla', (tester) async {
          await cargarFuentes144(tester);
          await montarPantalla144(
            tester,
            Celda144(t, e),
            repo: NotaPersonaRepositorioFalso(notas: notas),
            pantalla: Pantalla144.borradas,
          );
          expect(tester.takeException(), isNull);
          expectSinTextoFueraDeLosCostados144(tester, t);
          for (final id in ['b1', 'b2', 'b3']) {
            final tarjeta = find.byKey(ValueKey('borrada_$id'));
            await _traer(tester, tarjeta);
            final boton = find.descendant(of: tarjeta, matching: find.byType(TextButton));
            expect(boton, findsOneWidget, reason: 'la tarjeta $id lleva su «Restaurar» adentro');
            final rb = tester.getRect(boton);
            expect(rb.width, greaterThanOrEqualTo(48));
            expect(rb.height, greaterThanOrEqualTo(48));
            final rt = tester.getRect(
              find.descendant(of: tarjeta, matching: find.byType(Container)).first,
            );
            expect(
              rt.inflate(0.5).contains(rb.center),
              isTrue,
              reason: '$id: tarjeta $rt, botón $rb',
            );
            expect(rb.right, lessThanOrEqualTo(t.width + 0.5));
            if (id == 'b2') {
              // El texto largo ocupa todo el ancho que le deja el botón: no queda en una columna angosta.
              final texto = tester.getRect(
                find.descendant(of: tarjeta, matching: find.text(notas[1].texto)),
              );
              expect(texto.width, greaterThanOrEqualTo(90), reason: 'b2: columna del texto $texto');
            }
          }
          if (t == const Size(360, 640) && (e == 1.0 || e == 1.3 || e == 1.4 || e == 2.0)) {
            await capturar144(tester, 'qa573_e05_${t.width.toInt()}_x$e');
          }
        });
      }
    }

    testWidgets(
      'el lector: la nota por un lado y «Restaurar la nota del 05/10» por otro, sin «de el»',
      (tester) async {
        final s = tester.ensureSemantics();
        await montarPantalla144(
          tester,
          celdas144[2],
          repo: NotaPersonaRepositorioFalso(notas: notas),
          pantalla: Pantalla144.borradas,
        );
        expect(find.bySemanticsLabel('Restaurar la nota del 21/10'), findsNothing);
        expect(find.bySemanticsLabel('Restaurar la nota del 05/09'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('Restaurar la nota')), findsWidgets);
        expect(find.bySemanticsLabel(RegExp(r'Restaurar la nota de el ')), findsNothing);
        expect(find.bySemanticsLabel(RegExp('Corta')), findsOneWidget);
        s.dispose();
      },
    );

    testWidgets('dos toques seguidos en «Restaurar»: se restaura una sola vez', (tester) async {
      final repo = NotaPersonaRepositorioFalso(notas: notas)
        ..compuertas['restaurar'] = Completer<void>();
      await montarPantalla144(tester, celdas144[3], repo: repo, pantalla: Pantalla144.borradas);
      final boton = find.descendant(
        of: find.byKey(const ValueKey('borrada_b3')),
        matching: find.byType(TextButton),
      );
      await tester.tap(boton);
      await tester.pump();
      await tester.tap(boton, warnIfMissed: false);
      await tester.pump();
      expect(repo.cuantas('restaurar'), 1);
      repo.compuertas['restaurar']!.complete();
      await asentar(tester);
    });

    testWidgets('la restauración falla: la nota sigue en la lista y «Restaurar» vuelve a andar', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso(notas: notas)
        ..resultados['restaurar'] = [const FailureInesperado()];
      await montarPantalla144(tester, celdas144[3], repo: repo, pantalla: Pantalla144.borradas);
      final boton = find.descendant(
        of: find.byKey(const ValueKey('borrada_b3')),
        matching: find.byType(TextButton),
      );
      await tester.tap(boton);
      await asentar(tester);
      expect(find.byKey(const ValueKey('borrada_b3')), findsOneWidget);
      await tester.tap(boton);
      await asentar(tester);
      expect(repo.cuantas('restaurar'), 2);
    });
  });

  group('#143 · cuadro de la cuenta con valores anchos', () {
    for (final escala in [1.0, 1.5, 2.0]) {
      testWidgets('D·02 a 360×640 · $escala×: rótulos en un renglón y valores sin cortar', (
        tester,
      ) async {
        await baja.hojaEn(tester, baja.EstadoHoja.d02, escala: escala);
        expect(tester.takeException(), isNull);
        for (final rotulo in ['Comprado', 'Entregado', 'Pagado', 'Saldo']) {
          final f = find.text(rotulo);
          if (f.evaluate().isEmpty) continue;
          final p = tester.renderObject<RenderParagraph>(f);
          final cajas = p.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: rotulo.length),
          );
          expect(cajas.map((c) => c.top.round()).toSet().length, 1, reason: '«$rotulo» se parte');
        }
        if (escala == 2.0 || escala == 1.0) await baja.capturar(tester, 'qa573_d02_x$escala');
      });
    }
  });

  group('#444/#445 · iniciales del avatar', () {
    for (final escala in [1.0, 2.0, 3.0]) {
      testWidgets('iniciales anchas («WW») a $escala× en 320×568: caben en el círculo de 34 dp', (
        tester,
      ) async {
        await cargarFuentes205(tester);
        await montarHoja445(
          tester,
          contexto: contextoCon([clienteDePersonas('pw', 'Wendy', apellido: 'Wójcik')]),
          escala: escala,
          tamano: t320x568,
        );
        await asentar(tester);
        expect(tester.takeException(), isNull);
        final p = tester.renderObject<RenderParagraph>(find.text('WW'));
        expect(p.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(34));
        expect(p.getMaxIntrinsicHeight(34), lessThanOrEqualTo(34));
      });
    }
  });

  group('Hallazgos corregidos (QA #541)', () {
    // QA #541 — D·02 a 360×640 con el texto al 200 %: con el texto grande el rótulo y el valor del cuadro
    // van uno sobre el otro y el monto («$ 4.500») no se parte.
    testWidgets(
      'D·02 a 360×640 y 2,0×: los montos del cuadro de la cuenta no se parten en dos renglones',
      (tester) async {
        await baja.hojaEn(tester, baja.EstadoHoja.d02, escala: 2);
        var montos = 0;
        for (final e in find.byType(RichText).evaluate()) {
          final r = e.renderObject! as RenderParagraph;
          final t = r.text.toPlainText();
          if (!RegExp(r'^\$[\s ]\d').hasMatch(t) || t.length > 12) continue;
          montos += 1;
          final cajas = r.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: t.length),
          );
          expect(
            cajas.map((c) => c.top.round()).toSet().length,
            1,
            reason: '«$t» se parte en dos renglones',
          );
        }
        expect(montos, greaterThanOrEqualTo(3), reason: 'el cuadro lleva tres montos');
      },
    );

    // QA #541 — «Personas del espacio» (vista 32): el avatar (36 dp) no escala con el texto, como el de la
    // hoja de la casa: a 2,0× las iniciales caben en el círculo (decisión del 29/10, P1 del QA).
    testWidgets(
      'Personas del espacio a 360×640 y 2,0×: las iniciales caben en el círculo de 36 dp',
      (tester) async {
        await cargarFuentes205(tester);
        await montarClientes(
          tester,
          repo: PersonaRepositorioFalso()
            ..sembrar([clienteDePersonas('p1', 'Pedro', apellido: 'Gómez')]),
          escala: 2,
          tamano: const Size(360, 640),
        );
        await asentar(tester);
        final p = tester.renderObject<RenderParagraph>(find.text('PG').first);
        expect(p.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(36));
        expect(p.getMaxIntrinsicHeight(36), lessThanOrEqualTo(36));
      },
    );
  });
}

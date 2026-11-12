// QA r3 del paso «¿Con quién?» de la vista 39 (#449, PR #463, punta b79b6b9). Decisión del
// orquestador (23/10): si la segunda línea de dos homónimos («Cargada el dd/MM» o el teléfono
// enmascarado) también se repite, esas filas suman la hora de alta, en hora local HH:mm:
// «Cargada el 23/10 a las 15:40» o «Tel. 099 ••• 412 · Cargada el 23/10 a las 15:40»; el lector lee lo
// mismo; si coinciden hasta el minuto queda el orden de alta (la primera elegida), sin numerar.
import 'package:colportores_mobile/features/mapa/domain/value_objects/paso_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_con_quien.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_baja_205_arnes.dart'
    show cargarFuentes205, expectSinTextoFueraDeLosCostados205;
import '../../helpers/qa_vista39_449_arnes.dart';
import '../../helpers/qa_vista39_449_dup_arnes.dart';
import '../../helpers/qa_vista39_449_hora_arnes.dart';
import 'personas_arnes.dart' show asentar;

void main() {
  group('cuándo la fila suma la hora', () {
    testWidgets('dos homónimos sin teléfono el mismo día: cada una con su hora', (tester) async {
      await llegarAHora449(tester, EstadoHora449.sinTelefonoMismoDia);

      expect(find.text('Cargada el 23/10 a las 15:40'), findsOneWidget);
      expect(find.text('Cargada el 23/10 a las 16:05'), findsOneWidget);
      // Ni la línea vieja (sin hora) ni la hora en la «Ana» que no se repite.
      expect(find.text('Cargada el 23/10'), findsNothing);
      expect(find.textContaining('a las'), findsNWidgets(2));
    });

    testWidgets('el mismo teléfono enmascarado el mismo día: «Tel. … · Cargada el … a las …»', (
      tester,
    ) async {
      await llegarAHora449(tester, EstadoHora449.mismoTelefonoMismoDia);

      expect(find.text('Tel. 099 ••• 412 · Cargada el 23/10 a las 15:40'), findsOneWidget);
      expect(find.text('Tel. 099 ••• 412 · Cargada el 23/10 a las 16:05'), findsOneWidget);
      // El número entero nunca sale en pantalla.
      expect(find.textContaining('123'), findsNothing);
      expect(find.textContaining('555'), findsNothing);
    });

    testWidgets('el teléfono con otro formato que da la misma máscara también suma la hora', (
      tester,
    ) async {
      await montar449(
        tester,
        repo: PersonaRepositorioFalso()
          ..sembrar([
            persona449(
              'a',
              'Pedro',
              apellido: 'Gómez',
              telefono: '099 123 412',
              creada: local449(23, 15, 40),
            ),
            persona449(
              'b',
              'Pedro',
              apellido: 'Gómez',
              telefono: '099-555-412',
              creada: local449(23, 16, 5),
            ),
          ]),
      );

      expect(find.textContaining('a las 15:40'), findsOneWidget);
      expect(find.textContaining('a las 16:05'), findsOneWidget);
    });

    testWidgets('la hora se completa con ceros («09:07», «23:59») y es la local', (tester) async {
      await llegarAHora449(tester, EstadoHora449.nombreLargoConTelefono);

      expect(find.text('Tel. +598 ••• 456 · Cargada el 23/10 a las 09:07'), findsOneWidget);
      expect(find.text('Tel. +598 ••• 456 · Cargada el 23/10 a las 23:59'), findsOneWidget);
    });

    testWidgets('un instante en UTC se muestra en hora local, no en UTC', (tester) async {
      final a = DateTime.utc(2026, 10, 24, 2, 30);
      final b = DateTime.utc(2026, 10, 24, 2, 45);
      await montar449(
        tester,
        repo: PersonaRepositorioFalso()
          ..sembrar([
            persona449('a', 'Pedro', apellido: 'Gómez', creada: a),
            persona449('b', 'Pedro', apellido: 'Gómez', creada: b),
          ]),
      );

      expect(find.text(cargadaALas449(a)), findsOneWidget);
      expect(find.text(cargadaALas449(b)), findsOneWidget);
    });

    testWidgets('tres homónimos: la que tiene otro teléfono no suma hora, las otras dos sí', (
      tester,
    ) async {
      await montar449(
        tester,
        repo: PersonaRepositorioFalso()
          ..sembrar([
            persona449('a', 'Pedro', apellido: 'Gómez', creada: local449(23, 15, 40)),
            persona449('b', 'Pedro', apellido: 'Gómez', creada: local449(23, 16, 5)),
            persona449(
              'c',
              'Pedro',
              apellido: 'Gómez',
              telefono: '099 123 412',
              creada: local449(23, 17, 0),
            ),
          ]),
      );

      expect(find.text('Cargada el 23/10 a las 15:40'), findsOneWidget);
      expect(find.text('Cargada el 23/10 a las 16:05'), findsOneWidget);
      expect(find.text('Tel. 099 ••• 412'), findsOneWidget);
      expect(find.textContaining('17:00'), findsNothing);
    });

    testWidgets('homónimos de días distintos: la hora no hace falta y no aparece', (tester) async {
      await montar449(
        tester,
        repo: PersonaRepositorioFalso()
          ..sembrar([
            persona449('a', 'Pedro', apellido: 'Gómez', creada: local449(22, 15, 40)),
            persona449('b', 'Pedro', apellido: 'Gómez', creada: local449(23, 15, 40)),
          ]),
      );

      expect(find.text('Cargada el 22/10'), findsOneWidget);
      expect(find.text('Cargada el 23/10'), findsOneWidget);
      expect(find.textContaining('a las'), findsNothing);
    });

    testWidgets('dos parejas de homónimos: cada pareja decide por su cuenta', (tester) async {
      await montar449(
        tester,
        repo: PersonaRepositorioFalso()
          ..sembrar([
            persona449('a', 'Pedro', apellido: 'Gómez', creada: local449(23, 15, 40)),
            persona449('b', 'Pedro', apellido: 'Gómez', creada: local449(23, 16, 5)),
            persona449('c', 'Ana', apellido: 'Gómez', creada: local449(20, 10, 0)),
            persona449('d', 'ana', apellido: 'GÓMEZ', creada: local449(21, 10, 0)),
          ]),
      );

      expect(find.textContaining('a las'), findsNWidgets(2));
      expect(find.text('Cargada el 20/10'), findsOneWidget);
      expect(find.text('Cargada el 21/10'), findsOneWidget);
    });

    testWidgets('nombres distintos con la misma fecha de alta: la fila queda como el canvas', (
      tester,
    ) async {
      await montar449(
        tester,
        repo: PersonaRepositorioFalso()
          ..sembrar([
            persona449('a', 'Pedro', apellido: 'Gómez', creada: local449(23, 15, 40)),
            persona449('b', 'Pedro', apellido: 'Núñez', creada: local449(23, 15, 40)),
          ]),
      );

      expect(find.textContaining('Cargada el'), findsNothing);
      expect(find.textContaining('a las'), findsNothing);
    });
  });

  group('coinciden hasta el minuto', () {
    testWidgets('las dos filas dicen lo mismo, sin numerar ni nota, y la primera viene elegida', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await montar449(
        tester,
        repo: PersonaRepositorioFalso()
          ..sembrar([
            persona449('a', 'Pedro', apellido: 'Gómez', creada: local449(23, 15, 40, 5)),
            persona449('b', 'Pedro', apellido: 'Gómez', creada: local449(23, 15, 40, 50)),
          ]),
      );

      expect(find.text('Cargada el 23/10 a las 15:40'), findsNWidgets(2));
      expect(find.textContaining('(1)'), findsNothing);
      expect(find.textContaining('(2)'), findsNothing);
      expect(find.textContaining('Nota'), findsNothing);
      const etiqueta = 'Pedro Gómez. Cargada el 23/10 a las 15:40';
      final filas = find.bySemanticsLabel(etiqueta);
      expect(filas, findsNWidgets(2));
      expect(
        tester.getSemantics(filas.at(0)),
        isSemantics(label: etiqueta, hasCheckedState: true, isChecked: true),
      );
      expect(
        tester.getSemantics(filas.at(1)),
        isSemantics(label: etiqueta, hasCheckedState: true, isChecked: false),
      );
      handle.dispose();
    });

    testWidgets('sin tocar nada devuelve a la primera (orden de alta); tocando la segunda, a la '
        'segunda', (tester) async {
      final personas = [
        persona449('a', 'Pedro', apellido: 'Gómez', creada: local449(23, 15, 40, 5)),
        persona449('b', 'Pedro', apellido: 'Gómez', creada: local449(23, 15, 40, 50)),
      ];
      var r = await montar449(tester, repo: PersonaRepositorioFalso()..sembrar(personas));
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      expect(r.elegida!.personaId, 'a');

      r = await montar449(tester, repo: PersonaRepositorioFalso()..sembrar(personas));
      await tester.tap(find.text('Cargada el 23/10 a las 15:40').last);
      await tester.pump();
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      expect(r.elegida!.personaId, 'b');
    });
  });

  group('el lector de pantalla lee lo mismo que se ve', () {
    testWidgets('sin teléfono: nombre, hora de alta y saldo, en ese orden', (tester) async {
      final handle = tester.ensureSemantics();
      await llegarAHora449(tester, EstadoHora449.sinTelefonoMismoDia);

      expect(
        find.bySemanticsLabel('Pedro Gómez. Cargada el 23/10 a las 15:40. Saldo \$ 1.200'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Pedro Gómez. Cargada el 23/10 a las 16:05'), findsOneWidget);
      // «Ana Gómez» no se repite: ni dato ni hora.
      expect(find.bySemanticsLabel('Ana Gómez'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('con el mismo teléfono: teléfono terminado en…, hora de alta', (tester) async {
      final handle = tester.ensureSemantics();
      await llegarAHora449(tester, EstadoHora449.mismoTelefonoMismoDia);

      expect(
        find.bySemanticsLabel(
          'Pedro Gómez. Teléfono terminado en 412. Cargada el 23/10 a las 15:40',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Pedro Gómez. Teléfono terminado en 412. Cargada el 23/10 a las 16:05',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('«+ Alguien nuevo» crea un homónimo del mismo día', () {
    testWidgets('las dos filas pasan a llevar la hora y la nueva queda elegida', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([
          persona449('a', 'Pedro', apellido: 'Gómez', creada: DateTime.now()),
          persona449('b', 'Ana', apellido: 'Gómez', creada: DateTime.now()),
        ]);
      final r = await montar449(tester, repo: repo);
      expect(find.textContaining('Cargada el'), findsNothing);

      await tester.tap(find.text('+ Alguien nuevo'));
      await asentar(tester, 16);
      await tester.enterText(find.byType(TextField).at(0), 'Pedro');
      await tester.enterText(find.byType(TextField).at(1), 'Gómez');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar persona'));
      await asentar(tester, 16);

      expect(find.textContaining('Cargada el'), findsNWidgets(2));
      expect(find.textContaining('a las'), findsNWidgets(2));
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      expect(r.elegida!.personaId, repo.recibidas.single.persona.id);
    });
  });

  group('tamaños y texto grande, fuentes reales', () {
    for (final tamano in [t360x640, t412x915]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in EstadoHora449.values) {
          testWidgets(
            '${estado.name} · ${sufijo449(tamano, escala)}: sin overflow, la hora cabe y la fila '
            'se alcanza',
            (tester) async {
              await cargarFuentes205(tester);
              await llegarAHora449(tester, estado, tamano: tamano, escala: escala);

              expect(tester.takeException(), isNull);
              expectSinTextoFueraDeLosCostados205(tester, tamano);
              await capturar449(tester, 'hora_${estado.name}_${sufijo449(tamano, escala)}');

              final linea = find.textContaining('a las').first;
              await tester.ensureVisible(linea);
              await tester.pump();
              final r = tester.getRect(linea);
              expect(r.left, greaterThanOrEqualTo(0));
              expect(r.right, lessThanOrEqualTo(tamano.width));
              expect(r.bottom, lessThanOrEqualTo(tamano.height));
              final fila = find.ancestor(of: linea, matching: find.byType(InkWell)).first;
              expect(tester.getRect(fila).height, greaterThanOrEqualTo(48));
              await tester.ensureVisible(botonEmpezar449);
              await tester.pump();
              expect(tester.getRect(botonEmpezar449).height, greaterThanOrEqualTo(48));
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    for (final escala in [2.0, 3.0]) {
      testWidgets('nombreLargoConTelefono · 320×568 ×$escala: la línea más larga no se corta ni '
          'desborda', (tester) async {
        await cargarFuentes205(tester);
        await llegarAHora449(
          tester,
          EstadoHora449.nombreLargoConTelefono,
          tamano: t320x568,
          escala: escala,
        );

        expect(tester.takeException(), isNull);
        expectSinTextoFueraDeLosCostados205(tester, t320x568);
        await capturar449(tester, 'hora_larga_320_x$escala');
        final linea = find.textContaining('a las 09:07');
        await tester.scrollUntilVisible(linea, 100, scrollable: find.byType(Scrollable).last);
        await tester.pump();
        expect(tester.getRect(linea).right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('texto 2,0 en 360×640 con 30 homónimos con hora: se llega a la última y se elige', (
      tester,
    ) async {
      await cargarFuentes205(tester);
      final p = personasHora449(EstadoHora449.treinta);
      final r = await llegarAHora449(tester, EstadoHora449.treinta, tamano: t360x640, escala: 2);

      final ultima = find.text(cargadaALas449(p[29].persona.auditoria.createdAt));
      await tester.scrollUntilVisible(ultima, 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(ultima);
      await tester.pump();
      await tester.ensureVisible(botonEmpezar449);
      await tester.tap(botonEmpezar449);
      await asentar(tester);

      expect(r.elegida, p[29].aLaEntrevista);
    });
  });

  group('unidad · TextosConQuien', () {
    final sin1 = persona449('a', 'Pedro', apellido: 'Gómez', creada: local449(23, 15, 40));
    final sin2 = persona449('b', 'pedro', apellido: ' GÓMEZ ', creada: local449(23, 16, 5));
    final con1 = persona449(
      'c',
      'Pedro',
      apellido: 'Gómez',
      telefono: '099 123 412',
      creada: local449(23, 15, 40),
    );
    final con2 = persona449(
      'd',
      'Pedro',
      apellido: 'Gómez',
      telefono: '099 777 412',
      creada: local449(23, 16, 5),
    );

    test('paraDistinguir con hora', () {
      expect(
        TextosConQuien.paraDistinguir(sin1.persona, conHora: true),
        'Cargada el 23/10 a las 15:40',
      );
      expect(
        TextosConQuien.paraDistinguir(con1.persona, conHora: true),
        'Tel. 099 ••• 412 · Cargada el 23/10 a las 15:40',
      );
      expect(TextosConQuien.paraDistinguir(sin1.persona), 'Cargada el 23/10');
      expect(TextosConQuien.paraDistinguir(con1.persona), 'Tel. 099 ••• 412');
    });

    test('un teléfono de solo espacios cuenta como sin teléfono también con la hora', () {
      final p = persona449('e', 'Pedro', telefono: '   ', creada: local449(23, 0, 5));
      expect(
        TextosConQuien.paraDistinguir(p.persona, conHora: true),
        'Cargada el 23/10 a las 00:05',
      );
    });

    test('conSegundaLineaRepetida', () {
      expect(TextosConQuien.conSegundaLineaRepetida(const []), isEmpty);
      expect(TextosConQuien.conSegundaLineaRepetida([sin1]), isEmpty);
      // Sin mirar mayúsculas ni espacios de más.
      expect(TextosConQuien.conSegundaLineaRepetida([sin1, sin2]), {'a', 'b'});
      expect(TextosConQuien.conSegundaLineaRepetida([con1, con2]), {'c', 'd'});
      // Línea distinta (con y sin teléfono): ninguna.
      expect(TextosConQuien.conSegundaLineaRepetida([sin1, con1]), isEmpty);
      // Tres: solo las dos que comparten línea.
      expect(TextosConQuien.conSegundaLineaRepetida([sin1, sin2, con1]), {'a', 'b'});
      // Otro nombre con la misma fecha: no cuenta.
      final otro = persona449('f', 'Ana', apellido: 'Núñez', creada: local449(23, 15, 40));
      expect(TextosConQuien.conSegundaLineaRepetida([sin1, otro]), isEmpty);
    });

    test('filaParaLector: la hora solo cuenta si el nombre se repite', () {
      expect(TextosConQuien.filaParaLector(sin1, null, conHora: true), 'Pedro Gómez');
      expect(
        TextosConQuien.filaParaLector(sin1, 120000, nombreRepetido: true, conHora: true),
        'Pedro Gómez. Cargada el 23/10 a las 15:40. Saldo \$ 1.200',
      );
      expect(
        TextosConQuien.filaParaLector(con1, null, nombreRepetido: true, conHora: true),
        'Pedro Gómez. Teléfono terminado en 412. Cargada el 23/10 a las 15:40',
      );
      expect(
        TextosConQuien.filaParaLector(con1, null, nombreRepetido: true),
        'Pedro Gómez. Teléfono terminado en 412',
      );
    });
  });
}

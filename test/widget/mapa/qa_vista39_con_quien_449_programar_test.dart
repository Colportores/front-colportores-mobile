// QA r5 del paso «¿Con quién?» de la vista 39 (#449, PR #463, punta 1ce61fc). Con el merge de develop
// (#474) la rama trae el modo **programar** de la hoja, que era el artboard «Programar entrevista con
// varias personas» que #449 había diferido (decisión del 23/10: título «¿Con quién es la entrevista?»,
// «Seguir», la persona opcional con «Todavía no sé con quién», una sola persona o ninguna: el paso se
// salta). Acá se prueba la hoja misma en ese modo: textos, resultado, casos límite, tamaños y capturas.
import 'package:colportores_mobile/features/mapa/domain/entities/eleccion_de_cita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_de_la_entrevista.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/paso_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_baja_205_arnes.dart'
    show cargarFuentes205, expectSinTextoFueraDeLosCostados205;
import '../../helpers/qa_vista39_449_arnes.dart';
import '../../helpers/qa_vista39_449_programar_arnes.dart';
import 'hoja_con_quien_arnes.dart';
import 'personas_arnes.dart' show asentar;

/// Desplaza la lista como lo hace una persona hasta que [f] se construye y queda a la vista.
Future<void> _alcanzar(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      maxScrolls: 200,
      scrollable: find
          .descendant(of: find.byType(HojaConQuien), matching: find.byType(Scrollable))
          .first,
    );
  }
  await tester.ensureVisible(f);
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await _alcanzar(tester, f);
  await tester.pump();
  await tester.tap(f);
  await asentar(tester);
}

void main() {
  group('C·07 al programar · textos y resultado', () {
    testWidgets(
      'dado varias personas, cuando se abre, dice «¿Con quién es la entrevista?», «Seguir», '
      '«Todavía no sé con quién», «+ Alguien nuevo» y «Volver» (nada de «Empezar» ni el pasado)',
      (tester) async {
        await montarProgramar449(
          tester,
          repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2)),
        );

        expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
        expect(find.text('¿Con quién fue la entrevista?'), findsNothing);
        expect(botonSeguir449, findsOneWidget);
        expect(find.text('Empezar entrevista'), findsNothing);
        expect(filaTodaviaNoSe449, findsOneWidget);
        expect(find.text('Todavía no sé con quién'), findsOneWidget);
        expect(find.text('+ Alguien nuevo'), findsOneWidget);
        expect(botonVolver449, findsOneWidget);
        expect(find.text('Persona0 Gómez'), findsOneWidget);
        expect(find.text('Persona1 Gómez'), findsOneWidget);
      },
    );

    testWidgets('«Seguir» sin tocar nada devuelve la cita con la primera persona', (tester) async {
      final personas = personasDeLaCasa(3);
      final r = await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personas),
      );

      await _tocar(tester, botonSeguir449);

      expect(r.eleccion, CitaConPersona(personas.first.aLaEntrevista));
      expect(r.cierres, 1);
      expect(r.abiertas, 0);
    });

    testWidgets('elegir la tercera y «Seguir» devuelve la tercera, no la primera', (tester) async {
      final personas = personasDeLaCasa(3);
      final r = await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personas),
      );

      await _tocar(tester, find.text('Persona2 Gómez'));
      await _tocar(tester, botonSeguir449);

      expect(r.eleccion, CitaConPersona(personas[2].aLaEntrevista));
      expect(r.cierres, 1);
    });

    testWidgets('«Todavía no sé con quién» devuelve la cita sin persona y cierra una sola vez', (
      tester,
    ) async {
      final r = await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2)),
      );

      await _tocar(tester, filaTodaviaNoSe449);

      expect(r.eleccion, const CitaSinPersona());
      expect(r.eleccion!.espacioPersonaId, isNull);
      expect(r.cierres, 1);
      expect(r.abiertas, 0);
    });

    testWidgets('«Volver» cierra sin elección (null), con la elección que había tocado', (
      tester,
    ) async {
      final r = await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2)),
      );

      await _tocar(tester, find.text('Persona1 Gómez'));
      await _tocar(tester, botonVolver449);

      expect(r.eleccion, isNull);
      expect(r.cierres, 1);
      expect(r.abiertas, 0);
    });

    testWidgets('atrás (el gesto del sistema) también cierra sin elección', (tester) async {
      final r = await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2)),
      );

      final estado = tester.state<NavigatorState>(find.byType(Navigator));
      expect(await estado.maybePop(), isTrue);
      await asentar(tester);

      expect(r.eleccion, isNull);
      expect(r.cierres, 1);
    });

    testWidgets('una sola persona: no se abre la hoja y la cita va con ella', (tester) async {
      final personas = personasDeLaCasa(1);
      final r = await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personas),
      );

      expect(find.byType(HojaConQuien), findsNothing);
      expect(r.eleccion, CitaConPersona(personas.single.aLaEntrevista));
      expect(r.cierres, 1);
      expect(r.rutas.aperturas, 1, reason: 'solo la pantalla de arranque: nunca se abrió la hoja');
    });

    testWidgets('una casa sin personas: no se abre la hoja y la cita va sin persona (el nombre se '
        'pide al dar la entrevista)', (tester) async {
      final r = await montarProgramar449(tester);

      expect(find.byType(HojaConQuien), findsNothing);
      expect(find.text('NOMBRE'), findsNothing);
      expect(r.eleccion, const CitaSinPersona());
      expect(r.cierres, 1);
    });

    testWidgets(
      'la lista llega tarde con una sola persona: la hoja que se abrió «cargando» se cierra '
      'sola con la cita',
      (tester) async {
        final repo = PersonaRepositorioTardio();
        final r = await montarProgramar449(tester, repo: repo);
        expect(find.text('Cargando los clientes'), findsOneWidget);

        final personas = personasDeLaCasa(1);
        repo.emitir(personas);
        await asentar(tester);

        expect(r.eleccion, CitaConPersona(personas.single.aLaEntrevista));
        expect(r.cierres, 1);
        expect(r.abiertas, 0);
      },
    );

    testWidgets('la lista llega tarde sin nadie: la hoja se cierra sola con la cita sin persona', (
      tester,
    ) async {
      final repo = PersonaRepositorioTardio();
      final r = await montarProgramar449(tester, repo: repo);

      repo.emitir(const []);
      await asentar(tester);

      expect(r.eleccion, const CitaSinPersona());
      expect(r.cierres, 1);
      expect(r.abiertas, 0);
    });

    testWidgets(
      'la lista llega tarde con varias: pasa de «cargando» a la lista del modo programar',
      (tester) async {
        final repo = PersonaRepositorioTardio();
        await montarProgramar449(tester, repo: repo);
        expect(find.text('Cargando los clientes'), findsOneWidget);

        repo.emitir(personasDeLaCasa(2));
        await asentar(tester);

        expect(find.text('Cargando los clientes'), findsNothing);
        expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
        expect(filaTodaviaNoSe449, findsOneWidget);
      },
    );
  });

  group('C·07 al programar · acciones superpuestas y reintentos', () {
    testWidgets('doble toque en «Seguir»: una sola elección y un solo cierre', (tester) async {
      final personas = personasDeLaCasa(2);
      final r = await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personas),
      );
      await tester.ensureVisible(botonSeguir449);
      await tester.pump();

      await tester.tap(botonSeguir449);
      await tester.tap(botonSeguir449, warnIfMissed: false);
      await asentar(tester);

      expect(r.cierres, 1);
      expect(r.eleccion, CitaConPersona(personas.first.aLaEntrevista));
      expect(r.abiertas, 0);
    });

    testWidgets('doble toque en «Todavía no sé con quién»: un solo cierre', (tester) async {
      final r = await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2)),
      );
      await _alcanzar(tester, filaTodaviaNoSe449);
      await tester.pump();

      await tester.tap(filaTodaviaNoSe449);
      await tester.tap(filaTodaviaNoSe449, warnIfMissed: false);
      await asentar(tester);

      expect(r.cierres, 1);
      expect(r.eleccion, const CitaSinPersona());
      expect(r.abiertas, 0);
    });

    testWidgets('«Todavía no sé» y «Seguir» en el mismo cuadro: gana el primero y no se cierra dos '
        'veces', (tester) async {
      final r = await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2)),
      );
      await _alcanzar(tester, filaTodaviaNoSe449);
      await tester.pump();

      await tester.tap(filaTodaviaNoSe449);
      await tester.tap(botonSeguir449, warnIfMissed: false);
      await asentar(tester);

      expect(r.cierres, 1);
      expect(r.eleccion, const CitaSinPersona());
    });

    testWidgets('«Alguien nuevo» → alta → vuelve a la lista de programar con la nueva elegida y '
        '«Seguir» la devuelve', (tester) async {
      final repo = PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2));
      final r = await montarProgramar449(tester, repo: repo);

      await _tocar(tester, find.text('+ Alguien nuevo'));
      expect(find.text('Nueva persona'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Obligatorio'),
        'Jorge',
      );
      await tester.pump();
      await _tocar(tester, find.widgetWithText(FilledButton, 'Guardar persona'));

      expect(find.text('Nueva persona'), findsNothing);
      expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
      expect(find.text('Jorge'), findsOneWidget);
      expect(botonSeguir449, findsOneWidget);
      expect(filaTodaviaNoSe449, findsOneWidget);

      await _tocar(tester, botonSeguir449);
      expect(
        r.eleccion,
        CitaConPersona(
          PersonaDeLaEntrevista(
            personaId: repo.recibidas.single.persona.id,
            espacioPersonaId: repo.recibidas.single.vinculo.id,
          ),
        ),
      );
      expect(r.cierres, 1);
    });

    testWidgets(
      'cerrar el alta sin guardar vuelve a la lista de programar con la elección intacta',
      (tester) async {
        final personas = personasDeLaCasa(3);
        final r = await montarProgramar449(
          tester,
          repo: PersonaRepositorioFalso()..sembrar(personas),
        );

        await _tocar(tester, find.text('Persona1 Gómez'));
        await _tocar(tester, find.text('+ Alguien nuevo'));
        expect(find.text('Nueva persona'), findsOneWidget);
        final estado = tester.state<NavigatorState>(find.byType(Navigator));
        expect(await estado.maybePop(), isTrue);
        await asentar(tester);

        expect(find.text('Nueva persona'), findsNothing);
        expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
        await _tocar(tester, botonSeguir449);
        expect(r.eleccion, CitaConPersona(personas[1].aLaEntrevista));
      },
    );

    testWidgets('reentrar tras «Volver»: la hoja vuelve a abrirse con la primera elegida', (
      tester,
    ) async {
      final personas = personasDeLaCasa(2);
      final r = await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personas),
      );
      await _tocar(tester, find.text('Persona1 Gómez'));
      await _tocar(tester, botonVolver449);
      expect(r.eleccion, isNull);

      await abrirPaso(tester);
      await _tocar(tester, botonSeguir449);

      expect(r.eleccion, CitaConPersona(personas.first.aLaEntrevista));
      expect(r.cierres, 2);
    });

    testWidgets('lectura que falla: el aviso con «Reintentar» y «Volver» a mano; «Volver» cierra '
        'sin elección y no deja nada abierto', (tester) async {
      final r = await montarProgramar449(tester, repo: PersonaRepositorioQueFallaN(99));

      expect(find.text('No pudimos leer los clientes en tu teléfono.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      await _tocar(tester, find.text('Reintentar'));
      expect(
        find.text('Reintentar'),
        findsOneWidget,
        reason: 'sigue fallando: la acción sigue a mano',
      );
      await _tocar(tester, botonVolver449);

      expect(r.eleccion, isNull);
      expect(r.cierres, 1);
      expect(r.abiertas, 0);
    });

    testWidgets('lectura que falla una vez: «Reintentar» lleva a la lista de programar', (
      tester,
    ) async {
      final repo = PersonaRepositorioQueFallaN(2)..sembrar(personasDeLaCasa(2));
      await montarProgramar449(tester, repo: repo);
      expect(find.text('Reintentar'), findsOneWidget);

      await _tocar(tester, find.text('Reintentar'));

      expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
      expect(filaTodaviaNoSe449, findsOneWidget);
    });

    testWidgets(
      '30 personas de nombres largos: «Todavía no sé con quién» se alcanza al final de la '
      'lista, a 360×640 con texto 2,0',
      (tester) async {
        final r = await llegarAProgramar449(
          tester,
          EstadoProgramar449.treinta,
          tamano: t360x640,
          escala: 2,
        );

        await _tocar(tester, filaTodaviaNoSe449);

        expect(r.eleccion, const CitaSinPersona());
        expect(r.cierres, 1);
      },
    );
  });

  group('C·07 al programar · lector de pantalla y privacidad', () {
    testWidgets('«Todavía no sé con quién» es un botón con su nombre; las personas siguen siendo '
        'opciones marcables y «Alguien nuevo» no', (tester) async {
      final handle = tester.ensureSemantics();
      await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2)),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Todavía no sé con quién')),
        isSemantics(label: 'Todavía no sé con quién', isButton: true, hasCheckedState: false),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Persona0 Gómez')),
        isSemantics(label: 'Persona0 Gómez', hasCheckedState: true, isChecked: true),
      );
      handle.dispose();
    });

    testWidgets('el título es un encabezado para el lector', (tester) async {
      final handle = tester.ensureSemantics();
      await montarProgramar449(
        tester,
        repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2)),
      );

      expect(
        tester.getSemantics(find.text('¿Con quién es la entrevista?')),
        isSemantics(label: '¿Con quién es la entrevista?', isHeader: true),
      );
      handle.dispose();
    });

    test(
      'la elección de la cita no lleva nombres: solo ids y ni el toString ni los props los traen',
      () {
        final persona = personasDeLaCasa(1).single;
        final cita = CitaConPersona(persona.aLaEntrevista);

        expect(cita.toString(), isNot(contains('Persona0')));
        expect(cita.toString(), isNot(contains('Gómez')));
        expect(cita.props.toString(), isNot(contains('Gómez')));
        expect(const CitaSinPersona().espacioPersonaId, isNull);
      },
    );
  });

  group('C·07 al programar · tamaños, texto grande y capturas', () {
    for (final tamano in [t360x640, t412x915, t320x568]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in EstadoProgramar449.values) {
          testWidgets(
            '${estado.name} · ${sufijo449(tamano, escala)}: sin overflow, nada fuera de la '
            'pantalla, filas y acciones de 48 dp o más',
            (tester) async {
              await cargarFuentes205(tester);
              final r = await llegarAProgramar449(tester, estado, tamano: tamano, escala: escala);
              await tester.pump(const Duration(milliseconds: 300));

              expect(tester.takeException(), isNull);
              expectSinTextoFueraDeLosCostados205(tester, tamano);
              if (estado == EstadoProgramar449.dos || estado == EstadoProgramar449.treinta) {
                for (final f in [botonSeguir449, botonVolver449]) {
                  expect(tester.getSize(f).height, greaterThanOrEqualTo(48));
                }
                await _alcanzar(tester, filaTodaviaNoSe449);
                await tester.pump();
                expect(tester.getSize(filaTodaviaNoSe449).height, greaterThanOrEqualTo(48));
                expect(tester.getSize(filaTodaviaNoSe449).width, greaterThan(100));
              }
              await capturar449(tester, 'programar_${estado.name}_${sufijo449(tamano, escala)}');
              expect(r.cierres, 0);
            },
          );
        }
      }
    }
  });
}

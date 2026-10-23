// HU-VIS-005 / HU-UBI-008, vista 39: el paso «¿Con quién?» después de «Entrevista dada»
// (#449): R·04 («Entrevista dada: ¿con quién?», casa sin personas) y C·07 («¿Con quién?», varias).
// Cada estado del inventario y los casos límite de cada flujo: doble toque y doble envío, falla a
// mitad de la acción, dos acciones seguidas, volver atrás y reentrar, datos límite y texto al 200 %.
// No hay estado «sin conexión»: el paso es solo local, la persona no se sincroniza.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_de_la_entrevista.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/paso_con_quien.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'hoja_con_quien_arnes.dart';
import 'personas_arnes.dart';

const _empezar = 'Empezar entrevista';
const _nombre = 'Obligatorio';
const _apellido = 'Apellido';

Finder _campo(String sugerencia) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == sugerencia);

Finder get _botonEmpezar => find.widgetWithText(FilledButton, _empezar);
Finder get _botonVolver => find.widgetWithText(OutlinedButton, 'Volver');

Future<void> _escribir(WidgetTester tester, String sugerencia, String texto) async {
  await tester.enterText(_campo(sugerencia), texto);
  await tester.pump();
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await asentar(tester);
}

/// Lo que el paso le entrega a quien lo abrió cuando guardó la persona del alta [i] de [repo].
PersonaDeLaEntrevista _guardada(PersonaRepositorioFalso repo, [int i = 0]) => PersonaDeLaEntrevista(
  personaId: repo.recibidas[i].persona.id,
  espacioPersonaId: repo.recibidas[i].vinculo.id,
);

final _pedro = clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez');
final _ana = clienteDePersonas('ana', 'Ana', apellido: 'Gómez', minutos: 1);

PersonaRepositorioFalso _casaConDos() => PersonaRepositorioFalso()..sembrar([_pedro, _ana]);

void main() {
  group('R·04 · casa sin personas: el nombre alcanza', () {
    testWidgets('dado una casa sin personas, cuando se abre, muestra el título, la dirección, el '
        'candado, el nombre, el apellido opcional y las dos acciones', (tester) async {
      await montarConQuien(tester);

      expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
      expect(find.text('Mataojo 2044 · Depto 101 · con el nombre alcanza'), findsOneWidget);
      expect(
        find.text('Estos datos solo viven en tu celular. Nunca se suben a la nube.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('NOMBRE'), findsOneWidget);
      expect(find.text('APELLIDO (OPCIONAL)'), findsOneWidget);
      expect(_campo(_nombre), findsOneWidget);
      expect(_campo(_apellido), findsOneWidget);
      expect(_botonEmpezar, findsOneWidget);
      expect(_botonVolver, findsOneWidget);
      // Ni teléfono ni nota: es el alta corta.
      expect(find.text('TELÉFONO (OPCIONAL)'), findsNothing);
      expect(find.text('+ Alguien nuevo'), findsNothing);
      expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsNothing);
    });

    testWidgets('el nombre arranca con el foco, como dibuja el canvas', (tester) async {
      await montarConQuien(tester);

      final campo = tester.widget<TextField>(_campo(_nombre));
      expect(campo.focusNode!.hasFocus, isTrue);
    });

    testWidgets('dado nombre y apellido, cuando toca «Empezar entrevista», guarda a la persona en '
        'el espacio y devuelve con quién es', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarConQuien(tester, repo: repo);

      await _escribir(tester, _nombre, 'Pedro');
      await _escribir(tester, _apellido, 'Gómez');
      await _tocar(tester, _botonEmpezar);

      expect(repo.recibidas, hasLength(1));
      final alta = repo.recibidas.single;
      expect(alta.persona.nombre, 'Pedro');
      expect(alta.persona.apellido, 'Gómez');
      expect(alta.persona.telefono, isNull);
      expect(alta.nota, isNull);
      expect(alta.vinculo.espacioId, 'esp-1');
      expect(alta.vinculo.personaId, alta.persona.id);
      expect(resultado.elegida, _guardada(repo));
      expect(resultado.cierres, 1);
      expect(find.text('¿Con quién es la entrevista?'), findsNothing);
      expect(find.text('abrir paso'), findsOneWidget);
    });

    testWidgets('con el nombre alcanza: sin apellido también guarda', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarConQuien(tester, repo: repo);

      await _escribir(tester, _nombre, 'Juan');
      await _tocar(tester, _botonEmpezar);

      expect(repo.recibidas.single.persona.nombre, 'Juan');
      expect(repo.recibidas.single.persona.apellido, '');
      expect(resultado.elegida, _guardada(repo));
    });

    testWidgets('dado el nombre vacío, cuando toca «Empezar entrevista», dice qué falta, lleva el '
        'foco al campo y no guarda', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarConQuien(tester, repo: repo);

      await _tocar(tester, _botonEmpezar);

      expect(find.text('Escribí al menos el nombre.'), findsOneWidget);
      expect(tester.widget<TextField>(_campo(_nombre)).focusNode!.hasFocus, isTrue);
      expect(repo.recibidas, isEmpty);
      expect(resultado.cierres, 0);
      expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
    });

    testWidgets('dado un nombre de una letra, dice que necesita al menos 2', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarConQuien(tester, repo: repo);

      await _escribir(tester, _nombre, 'A');
      await _tocar(tester, _botonEmpezar);

      expect(find.text('El nombre necesita al menos 2 letras.'), findsOneWidget);
      expect(repo.recibidas, isEmpty);
    });

    testWidgets('«Volver» cierra sin guardar nada', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarConQuien(tester, repo: repo);

      await _escribir(tester, _nombre, 'Pedro');
      await _tocar(tester, _botonVolver);

      expect(resultado.elegida, isNull);
      expect(resultado.cierres, 1);
      expect(repo.recibidas, isEmpty);
      expect(find.text('¿Con quién es la entrevista?'), findsNothing);
    });

    testWidgets('el atrás del sistema cierra sin guardar nada', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarConQuien(tester, repo: repo);

      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(resultado.elegida, isNull);
      expect(resultado.cierres, 1);
      expect(repo.recibidas, isEmpty);
    });

    group('casos límite', () {
      testWidgets('doble toque en «Empezar entrevista»: una sola persona, un solo cierre', (
        tester,
      ) async {
        final compuerta = Completer<void>();
        final repo = PersonaRepositorioFalso(compuerta: compuerta);
        final resultado = await montarConQuien(tester, repo: repo);
        await _escribir(tester, _nombre, 'Pedro');

        // Dos toques seguidos, sin un solo fotograma entre ellos.
        await tester.tap(_botonEmpezar);
        await tester.tap(_botonEmpezar);
        await tester.pump();
        compuerta.complete();
        await asentar(tester);

        expect(repo.recibidas, hasLength(1));
        expect(resultado.cierres, 1);
        expect(resultado.rutas.cierres, 1);
        expect(resultado.abiertas, 0);
        expect(resultado.elegida, _guardada(repo));
        expect(find.text('abrir paso'), findsOneWidget);
      });

      testWidgets('doble activación por accesibilidad de «Empezar entrevista»: una sola persona', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final compuerta = Completer<void>();
        final repo = PersonaRepositorioFalso(compuerta: compuerta);
        final resultado = await montarConQuien(tester, repo: repo);
        await _escribir(tester, _nombre, 'Pedro');

        // Las acciones de accesibilidad no pasan por la ruta que ignora el toque mientras se cierra.
        final boton = find.semantics.byLabel(_empezar);
        tester.semantics.performAction(boton, SemanticsAction.tap);
        tester.semantics.performAction(boton, SemanticsAction.tap);
        await tester.pump();
        compuerta.complete();
        await asentar(tester);

        expect(repo.recibidas, hasLength(1));
        expect(resultado.cierres, 1);
        expect(resultado.rutas.cierres, 1);
        expect(resultado.elegida, _guardada(repo));
        handle.dispose();
      });

      testWidgets('mientras guarda: dice «Guardando…», los campos no se editan, «Volver» está '
          'apagado y el atrás no cierra', (tester) async {
        final compuerta = Completer<void>();
        final repo = PersonaRepositorioFalso(compuerta: compuerta);
        final resultado = await montarConQuien(tester, repo: repo);
        await _escribir(tester, _nombre, 'Pedro');

        await tester.tap(_botonEmpezar);
        await tester.pump();
        // Dos acciones seguidas antes de que termine la primera: «Volver» y el atrás.
        await tester.tap(_botonVolver, warnIfMissed: false);
        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(find.text('Guardando…'), findsOneWidget);
        expect(tester.widget<OutlinedButton>(_botonVolver).onPressed, isNull);
        expect(tester.widget<TextField>(_campo(_nombre)).readOnly, isTrue);
        expect(resultado.cierres, 0);
        expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);

        compuerta.complete();
        await asentar(tester);

        expect(resultado.cierres, 1);
        expect(resultado.elegida, _guardada(repo));
      });

      testWidgets('falla a mitad: el aviso dice qué hacer, lo escrito se conserva, la acción '
          'vuelve a estar habilitada y nada queda «ocupado»', (tester) async {
        final repo = PersonaRepositorioFalso(resultados: [fallaDeGuardado]);
        final resultado = await montarConQuien(tester, repo: repo);
        await _escribir(tester, _nombre, 'Pedro');
        await _escribir(tester, _apellido, 'Gómez');

        await _tocar(tester, _botonEmpezar);

        expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsOneWidget);
        expect(find.text('Guardando…'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.widget<FilledButton>(_botonEmpezar).onPressed, isNotNull);
        expect(tester.widget<OutlinedButton>(_botonVolver).onPressed, isNotNull);
        expect(find.text('Pedro'), findsOneWidget);
        expect(find.text('Gómez'), findsOneWidget);
        expect(resultado.cierres, 0);
      });

      testWidgets('reintentar tras la falla no crea dos personas: repite los mismos ids', (
        tester,
      ) async {
        final repo = PersonaRepositorioFalso(resultados: [fallaDeGuardado]);
        final resultado = await montarConQuien(tester, repo: repo);
        await _escribir(tester, _nombre, 'Pedro');

        await _tocar(tester, _botonEmpezar);
        await _tocar(tester, _botonEmpezar);

        expect(repo.recibidas, hasLength(2));
        expect(repo.recibidas[1].persona.id, repo.recibidas[0].persona.id);
        expect(repo.recibidas[1].vinculo.id, repo.recibidas[0].vinculo.id);
        expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsNothing);
        expect(resultado.elegida, _guardada(repo, 1));
        expect(resultado.cierres, 1);
      });

      testWidgets('volver y reentrar: el formulario arranca vacío, sin el aviso ni el error', (
        tester,
      ) async {
        final repo = PersonaRepositorioFalso(resultados: [fallaDeGuardado]);
        final resultado = await montarConQuien(tester, repo: repo);
        await _escribir(tester, _nombre, 'Pedro');
        await _tocar(tester, _botonEmpezar);
        expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsOneWidget);
        await _tocar(tester, _botonVolver);
        expect(resultado.elegida, isNull);

        await abrirPaso(tester);

        expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
        expect(find.text('Pedro'), findsNothing);
        expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsNothing);
        expect(find.text('El nombre necesita al menos 2 letras.'), findsNothing);
        expect(find.text('Escribí al menos el nombre.'), findsNothing);
      });

      testWidgets('el repositorio dice que el espacio ya no está: muestra su mensaje y se puede '
          'volver', (tester) async {
        final repo = PersonaRepositorioFalso(
          resultados: [
            const FailureValidacion(campos: {'espacio': 'El espacio ya no existe.'}),
          ],
        );
        await montarConQuien(tester, repo: repo);
        await _escribir(tester, _nombre, 'Pedro');

        await _tocar(tester, _botonEmpezar);

        expect(find.text('El espacio ya no existe.'), findsOneWidget);
        expect(tester.widget<OutlinedButton>(_botonVolver).onPressed, isNotNull);
      });

      testWidgets('nombre y apellido de 80 letras: el campo corta a 60 y no desborda', (
        tester,
      ) async {
        final repo = PersonaRepositorioFalso();
        await montarConQuien(tester, repo: repo);

        await _escribir(tester, _nombre, 'N' * 80);
        await _escribir(tester, _apellido, 'A' * 80);
        await _tocar(tester, _botonEmpezar);

        expect(repo.recibidas.single.persona.nombre, 'N' * 60);
        expect(repo.recibidas.single.persona.apellido, 'A' * 60);
        expect(tester.takeException(), isNull);
      });

      for (final escala in [2.0, 3.0]) {
        testWidgets('a 320×568 con el texto al ${(escala * 100).round()} % y el teclado '
            'abierto: no desborda y la acción se alcanza', (tester) async {
          final repo = PersonaRepositorioFalso();
          final resultado = await montarConQuien(
            tester,
            repo: repo,
            escala: escala,
            tamano: const Size(320, 568),
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 250);
          await asentar(tester);
          await _escribir(tester, _nombre, 'María de los Ángeles');
          await _escribir(tester, _apellido, 'Fernández de la Peña y Rodríguez');

          expect(tester.takeException(), isNull);
          await _tocar(tester, _botonEmpezar);

          expect(tester.takeException(), isNull);
          expect(resultado.elegida, _guardada(repo));
        });
      }
    });
  });

  group('C·07 · casa con personas: ¿con quién?', () {
    testWidgets('dado dos personas, cuando se abre, las lista con «+ Alguien nuevo» y las dos '
        'acciones; viene elegida la primera', (tester) async {
      final handle = tester.ensureSemantics();
      await montarConQuien(tester, repo: _casaConDos());

      expect(find.text('¿Con quién fue la entrevista?'), findsOneWidget);
      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.text('Ana Gómez'), findsOneWidget);
      expect(find.text('+ Alguien nuevo'), findsOneWidget);
      expect(find.text('Con el nombre alcanza'), findsOneWidget);
      expect(_botonEmpezar, findsOneWidget);
      expect(_botonVolver, findsOneWidget);
      // No es el formulario de R·04.
      expect(_campo(_nombre), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Pedro Gómez')),
        isSemantics(
          label: 'Pedro Gómez',
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Ana Gómez')),
        isSemantics(
          label: 'Ana Gómez',
          hasCheckedState: true,
          isChecked: false,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('la persona con saldo lo muestra debajo del nombre, y el lector lo lee junto', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await montarConQuien(tester, repo: _casaConDos(), saldos: SaldosFalsos({'pedro': 120000}));

      expect(find.text('Saldo \$ 1.200'), findsOneWidget);
      expect(find.bySemanticsLabel('Pedro Gómez. Saldo \$ 1.200'), findsOneWidget);
      expect(find.bySemanticsLabel('Ana Gómez'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('si no se pudo leer el saldo, las filas salen sin saldo y se puede elegir igual', (
      tester,
    ) async {
      final resultado = await montarConQuien(
        tester,
        repo: _casaConDos(),
        saldos: SaldosFalsos(const {}, falla: true),
      );

      expect(find.textContaining('Saldo'), findsNothing);
      await _tocar(tester, find.text('Ana Gómez'));
      await _tocar(tester, _botonEmpezar);

      expect(resultado.elegida, _ana.aLaEntrevista);
    });

    testWidgets('dado que elige a la segunda, cuando toca «Empezar entrevista», devuelve a esa '
        'persona y no guarda nada', (tester) async {
      final repo = _casaConDos();
      final resultado = await montarConQuien(tester, repo: repo);

      await _tocar(tester, find.text('Ana Gómez'));
      await _tocar(tester, _botonEmpezar);

      expect(resultado.elegida, _ana.aLaEntrevista);
      expect(resultado.elegida!.espacioPersonaId, 'ep-ana');
      expect(resultado.cierres, 1);
      expect(repo.recibidas, isEmpty);
    });

    testWidgets('sin tocar nada, «Empezar entrevista» devuelve a la primera', (tester) async {
      final resultado = await montarConQuien(tester, repo: _casaConDos());

      await _tocar(tester, _botonEmpezar);

      expect(resultado.elegida, _pedro.aLaEntrevista);
    });

    testWidgets('«Volver» y el atrás del sistema cierran sin elegir', (tester) async {
      final resultado = await montarConQuien(tester, repo: _casaConDos());

      await _tocar(tester, _botonVolver);
      expect(resultado.elegida, isNull);
      expect(resultado.cierres, 1);

      await abrirPaso(tester);
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(resultado.elegida, isNull);
      expect(resultado.cierres, 2);
    });

    group('una sola persona: el paso se salta', () {
      testWidgets('no muestra la hoja y devuelve a esa persona', (tester) async {
        final repo = PersonaRepositorioFalso()..sembrar([_pedro]);
        final resultado = await montarConQuien(tester, repo: repo);

        expect(resultado.elegida, _pedro.aLaEntrevista);
        expect(resultado.cierres, 1);
        expect(find.text('Volver'), findsNothing);
        expect(find.text('¿Con quién fue la entrevista?'), findsNothing);
        expect(find.text('¿Con quién es la entrevista?'), findsNothing);
        expect(repo.recibidas, isEmpty);
      });

      testWidgets('si la lista llega tarde, la hoja espera cargando y se cierra sola con esa '
          'persona', (tester) async {
        final repo = PersonaRepositorioTardio();
        final resultado = await montarConQuien(tester, repo: repo);

        expect(find.text('Cargando los clientes'), findsOneWidget);
        expect(resultado.cierres, 0);

        repo.emitir([_pedro]);
        await asentar(tester);

        expect(resultado.elegida, _pedro.aLaEntrevista);
        expect(resultado.cierres, 1);
        expect(find.text('Cargando los clientes'), findsNothing);
      });
    });

    group('+ Alguien nuevo', () {
      Future<void> altaDeJorge(WidgetTester tester) async {
        await _escribir(tester, _nombre, 'Jorge');
        await _tocar(tester, find.widgetWithText(FilledButton, 'Guardar persona'));
      }

      testWidgets('abre el alta de persona del mismo espacio y vuelve al paso con la persona nueva '
          'en la lista y elegida', (tester) async {
        final repo = _casaConDos();
        final resultado = await montarConQuien(tester, repo: repo);
        final handle = tester.ensureSemantics();

        await _tocar(tester, find.text('+ Alguien nuevo'));
        expect(find.text('Nueva persona'), findsOneWidget);
        expect(find.text('Mataojo 2044 · Depto 101'), findsOneWidget);
        await altaDeJorge(tester);

        expect(find.text('Nueva persona'), findsNothing);
        expect(find.text('¿Con quién fue la entrevista?'), findsOneWidget);
        expect(find.text('Jorge'), findsOneWidget);
        expect(repo.recibidas.single.vinculo.espacioId, 'esp-1');
        expect(
          tester.getSemantics(find.bySemanticsLabel('Jorge')),
          isSemantics(label: 'Jorge', hasCheckedState: true, isChecked: true),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Pedro Gómez')),
          isSemantics(label: 'Pedro Gómez', hasCheckedState: true, isChecked: false),
        );

        await _tocar(tester, _botonEmpezar);
        expect(resultado.elegida, _guardada(repo));
        expect(resultado.cierres, 1);
        handle.dispose();
      });

      testWidgets('anuncia al lector de pantalla que guardó a la persona', (tester) async {
        final handle = tester.ensureSemantics();
        await montarConQuien(tester, repo: _casaConDos());
        await _tocar(tester, find.text('+ Alguien nuevo'));
        tester.takeAnnouncements();

        await altaDeJorge(tester);

        expect(tester.takeAnnouncements().map((a) => a.message), [
          'Guardamos a Jorge en este teléfono.',
        ]);
        handle.dispose();
      });

      testWidgets('cerrar el alta sin guardar vuelve al paso con la elección intacta', (
        tester,
      ) async {
        final repo = _casaConDos();
        final resultado = await montarConQuien(tester, repo: repo);
        await _tocar(tester, find.text('Ana Gómez'));

        await _tocar(tester, find.text('+ Alguien nuevo'));
        await _tocar(tester, find.byTooltip('Cerrar'));

        expect(find.text('¿Con quién fue la entrevista?'), findsOneWidget);
        expect(repo.recibidas, isEmpty);
        await _tocar(tester, _botonEmpezar);
        expect(resultado.elegida, _ana.aLaEntrevista);
      });

      testWidgets('doble toque en «+ Alguien nuevo»: abre una sola alta', (tester) async {
        final nuevo = find.text('+ Alguien nuevo');

        final resultado = await montarConQuien(tester, repo: _casaConDos());
        await tester.tap(nuevo);
        await tester.tap(nuevo, warnIfMissed: false);
        await asentar(tester);

        // La hoja y una sola alta encima.
        expect(resultado.abiertas, 2);
        expect(find.text('Nueva persona'), findsOneWidget);
        await _tocar(tester, find.byTooltip('Cerrar'));
        expect(find.text('Nueva persona'), findsNothing);
        expect(find.text('¿Con quién fue la entrevista?'), findsOneWidget);
      });

      testWidgets('doble activación por accesibilidad de «+ Alguien nuevo»: abre una sola alta', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final resultado = await montarConQuien(tester, repo: _casaConDos());

        final fila = find.semantics.byLabel('+ Alguien nuevo. Con el nombre alcanza');
        tester.semantics.performAction(fila, SemanticsAction.tap);
        tester.semantics.performAction(fila, SemanticsAction.tap);
        await asentar(tester);

        expect(resultado.abiertas, 2);
        await _tocar(tester, find.byTooltip('Cerrar'));
        expect(find.text('Nueva persona'), findsNothing);
        expect(find.text('¿Con quién fue la entrevista?'), findsOneWidget);
        handle.dispose();
      });

      testWidgets('tras volver del alta se puede abrir otra vez', (tester) async {
        await montarConQuien(tester, repo: _casaConDos());

        await _tocar(tester, find.text('+ Alguien nuevo'));
        await _tocar(tester, find.byTooltip('Cerrar'));
        await _tocar(tester, find.text('+ Alguien nuevo'));

        expect(find.text('Nueva persona'), findsOneWidget);
      });
    });

    group('casos límite', () {
      testWidgets('doble toque en «Empezar entrevista»: un solo cierre, la pantalla de abajo '
          'sigue ahí', (tester) async {
        final resultado = await montarConQuien(tester, repo: _casaConDos());

        await tester.tap(_botonEmpezar);
        await tester.tap(_botonEmpezar, warnIfMissed: false);
        await asentar(tester);

        expect(resultado.cierres, 1);
        expect(resultado.rutas.cierres, 1);
        expect(resultado.abiertas, 0);
        expect(resultado.elegida, _pedro.aLaEntrevista);
        expect(find.text('abrir paso'), findsOneWidget);
      });

      testWidgets('doble activación por accesibilidad de «Empezar entrevista»: un solo cierre', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final resultado = await montarConQuien(tester, repo: _casaConDos());

        final boton = find.semantics.byLabel(_empezar);
        tester.semantics.performAction(boton, SemanticsAction.tap);
        tester.semantics.performAction(boton, SemanticsAction.tap);
        await asentar(tester);

        expect(resultado.cierres, 1);
        expect(resultado.rutas.cierres, 1);
        expect(resultado.abiertas, 0);
        expect(resultado.elegida, _pedro.aLaEntrevista);
        handle.dispose();
      });

      testWidgets('dos acciones seguidas: elegir a otra y tocar «Empezar» antes de que se pinte '
          'devuelve a la última elegida', (tester) async {
        final resultado = await montarConQuien(tester, repo: _casaConDos());

        await tester.tap(find.text('Ana Gómez'));
        await tester.tap(_botonEmpezar);
        await asentar(tester);

        expect(resultado.elegida, _ana.aLaEntrevista);
        expect(resultado.cierres, 1);
      });

      testWidgets('volver y reentrar: la elección vuelve a la primera', (tester) async {
        final resultado = await montarConQuien(tester, repo: _casaConDos());
        await _tocar(tester, find.text('Ana Gómez'));
        await _tocar(tester, _botonVolver);
        expect(resultado.elegida, isNull);

        await abrirPaso(tester);
        await _tocar(tester, _botonEmpezar);

        expect(resultado.elegida, _pedro.aLaEntrevista);
      });

      testWidgets('60 personas: la acción queda a la vista, «+ Alguien nuevo» está al final del '
          'desplazable y se puede elegir una del medio', (tester) async {
        final repo = PersonaRepositorioFalso()..sembrar(personasDeLaCasa(60));
        final resultado = await montarConQuien(tester, repo: repo);
        final lista = find
            .descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable))
            .first;

        expect(tester.getRect(_botonEmpezar).bottom, lessThanOrEqualTo(844));
        await tester.scrollUntilVisible(find.text('Persona40 Gómez'), 300, scrollable: lista);
        await tester.tap(find.text('Persona40 Gómez'));
        await tester.pump();
        await tester.scrollUntilVisible(find.text('+ Alguien nuevo'), 300, scrollable: lista);
        expect(find.text('+ Alguien nuevo'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _tocar(tester, _botonEmpezar);
        expect(resultado.elegida?.personaId, 'p40');
      });

      testWidgets('nombres muy largos: se parten en renglones sin desbordar', (tester) async {
        final repo = PersonaRepositorioFalso()
          ..sembrar([
            clienteDePersonas(
              'larga',
              'María de los Ángeles Concepción',
              apellido: 'Fernández de la Peña y Rodríguez Ibarburu',
            ),
            clienteDePersonas('x', 'N' * 60, apellido: 'A' * 60, minutos: 1),
          ]);
        await montarConQuien(tester, repo: repo, tamano: const Size(320, 568));

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Ibarburu'), findsOneWidget);
        expect(tester.getRect(find.textContaining('Ibarburu')).right, lessThanOrEqualTo(320));
      });

      for (final escala in [2.0, 3.0]) {
        testWidgets('a 320×568 con el texto al ${(escala * 100).round()} %: no desborda, el '
            'desplazable llega a «+ Alguien nuevo» y las acciones se alcanzan', (tester) async {
          final resultado = await montarConQuien(
            tester,
            repo: _casaConDos(),
            saldos: SaldosFalsos({'pedro': 123456}),
            escala: escala,
            tamano: const Size(320, 568),
          );
          final lista = find
              .descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable))
              .first;

          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(find.text('Saldo \$ 1.234,56'), 100, scrollable: lista);
          expect(find.text('Saldo \$ 1.234,56'), findsOneWidget);
          await tester.scrollUntilVisible(find.text('+ Alguien nuevo'), 100, scrollable: lista);
          expect(tester.takeException(), isNull);
          await _tocar(tester, _botonEmpezar);

          expect(resultado.elegida, _pedro.aLaEntrevista);
        });
      }

      testWidgets('cumple las guías de toque con nombre y de tamaño de objetivo', (tester) async {
        final handle = tester.ensureSemantics();
        await montarConQuien(tester, repo: _casaConDos(), saldos: SaldosFalsos({'pedro': 120000}));

        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('el saldo y los textos chicos cumplen el contraste', (tester) async {
        final handle = tester.ensureSemantics();
        await montarConQuien(tester, repo: _casaConDos(), saldos: SaldosFalsos({'pedro': 120000}));
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    });
  });

  group('estados que el canvas no dibuja: cargando y no se pudo leer', () {
    testWidgets('cargando: se ve el estado, no hay formulario ni lista y «Volver» cierra', (
      tester,
    ) async {
      final resultado = await montarConQuien(tester, repo: PersonaRepositorioTardio());

      expect(find.text('Cargando los clientes'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_campo(_nombre), findsNothing);
      expect(_botonEmpezar, findsNothing);

      await tester.tap(_botonVolver);
      await asentar(tester);

      expect(resultado.elegida, isNull);
      expect(resultado.cierres, 1);
    });

    testWidgets('no se pudo leer: dice qué pasó y qué hacer, y «Reintentar» abre el paso que '
        'corresponde', (tester) async {
      final repo = PersonaRepositorioQueFallaN(2);
      final resultado = await montarConQuien(tester, repo: repo);

      expect(find.text('No pudimos leer los clientes en tu teléfono.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(_botonVolver, findsOneWidget);
      expect(_botonEmpezar, findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await asentar(tester);

      expect(find.text('No pudimos leer los clientes en tu teléfono.'), findsNothing);
      expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
      expect(resultado.cierres, 0);
    });

    testWidgets('no se pudo leer y «Volver» cierra sin elegir', (tester) async {
      final resultado = await montarConQuien(tester, repo: PersonaRepositorioQueFallaN(99));

      expect(find.text('No pudimos leer los clientes en tu teléfono.'), findsOneWidget);
      await tester.tap(_botonVolver);
      await asentar(tester);

      expect(resultado.elegida, isNull);
      expect(resultado.cierres, 1);
    });
  });
}

// Las notas de una persona (HU-UBI-012, vista 32E): E·01 lista, E·03 opciones, E·04 borrada con
// «Deshacer», E·06 vacío, y los estados de cargando, error y solo lectura.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_persona_falsos.dart';
import 'notas_persona_arnes.dart';

void main() {
  const privacidad = 'Estas notas viven solo en tu celular.';

  group('E·01 notas por fecha', () {
    testWidgets(
      'dado una persona con dos notas, cuando abro sus notas, veo el título, el aviso fijo y las notas de la más nueva a la más vieja',
      (tester) async {
        await montarNotas(tester, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));

        expect(find.text('Notas de María'), findsOneWidget);
        expect(find.text(privacidad), findsOneWidget);
        expect(find.text('+ Nueva nota'), findsOneWidget);
        expect(find.text('HOY 14:20'), findsOneWidget);
        expect(find.text('05/10'), findsOneWidget);
        expect(
          find.text('Pidió volver el sábado con el esposo. Le interesa Nuestros Hijos.'),
          findsOneWidget,
        );
        expect(find.textContaining('Ver borradas'), findsNothing);
        final arriba = tester.getTopLeft(find.byKey(const ValueKey('nota_hoy'))).dy;
        final abajo = tester.getTopLeft(find.byKey(const ValueKey('nota_vieja'))).dy;
        expect(arriba, lessThan(abajo));
      },
    );

    testWidgets(
      'dado una lista larga, cuando bajo, «+ Nueva nota» no se mueve y la última nota se alcanza',
      (tester) async {
        final muchas = [
          for (var i = 0; i < 30; i++)
            notaDePrueba('n$i', 'Nota $i', creada: DateTime(2026, 9, 1).add(Duration(days: i))),
        ];
        await montarNotas(tester, repo: NotaPersonaRepositorioFalso(notas: muchas));
        final botonAntes = tester.getTopLeft(find.text('+ Nueva nota'));

        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await asentar(tester);

        expect(tester.getTopLeft(find.text('+ Nueva nota')), botonAntes);
        await tester.scrollUntilVisible(
          find.text('Nota 0'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Nota 0'), findsOneWidget);
        expect(tester.getTopLeft(find.text('+ Nueva nota')), botonAntes);
      },
    );

    testWidgets('dado una nota de 5000 caracteres, cuando la veo, se muestra entera', (
      tester,
    ) async {
      final larga = 'Línea de prueba. ' * 300;
      await montarNotas(
        tester,
        repo: NotaPersonaRepositorioFalso(notas: [notaDePrueba('larga', larga.trim())]),
      );

      expect(find.text(larga.trim()), findsOneWidget);
    });

    testWidgets(
      'dado una nota, cuando la miro, no hay «Llamar» ni «Compartir» ni texto seleccionable',
      (tester) async {
        await montarNotas(tester, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));

        expect(find.text('Llamar'), findsNothing);
        expect(find.text('Compartir'), findsNothing);
        expect(find.byType(SelectableText), findsNothing);
        expect(find.byType(SelectionArea), findsNothing);
      },
    );

    testWidgets('dado que salgo y vuelvo a entrar, cuando reabro las notas, siguen todas', (
      tester,
    ) async {
      await montarNotas(tester, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));

      await tester.tap(find.byTooltip('Volver'));
      await asentar(tester);
      expect(find.text('Notas de María'), findsNothing);
      await tester.tap(find.text('abrir notas'));
      await asentar(tester);

      expect(find.text('Notas de María'), findsOneWidget);
      expect(find.byKey(const ValueKey('nota_hoy')), findsOneWidget);
      expect(find.byKey(const ValueKey('nota_vieja')), findsOneWidget);
    });

    testWidgets(
      'dado el texto al 200 % en un teléfono chico, cuando veo las notas, nada se desborda y se puede llegar a todas',
      (tester) async {
        await montarNotas(
          tester,
          repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()),
          escala: 2,
          tamano: const Size(320, 568),
        );

        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('nota_vieja')),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('+ Nueva nota'), findsOneWidget);
      },
    );

    testWidgets(
      'dado las notas, cuando las lee el lector de pantalla, cada una dice su fecha y su texto y se puede tocar',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await montarNotas(tester, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));

        const etiqueta =
            'hoy a las 14:20. Pidió volver el sábado con el esposo. Le interesa Nuestros Hijos.';
        expect(find.bySemanticsLabel(etiqueta), findsOneWidget);
        final nodo = tester.getSemantics(find.bySemanticsLabel(etiqueta));
        // ignore: deprecated_member_use
        expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantica.dispose();
      },
    );
  });

  group('E·06, cargando, error y persona', () {
    testWidgets(
      'dado una persona sin notas, cuando abro sus notas, veo «Todavía no hay notas» y puedo agregar una',
      (tester) async {
        await montarNotas(tester);

        expect(find.text('Todavía no hay notas'), findsOneWidget);
        expect(find.text('Anotá lo que te sirva para la próxima visita.'), findsOneWidget);
        expect(find.text('+ Nueva nota'), findsOneWidget);
        expect(find.text(privacidad), findsOneWidget);
      },
    );

    testWidgets(
      'dado que las notas todavía no llegaron, cuando miro, veo el estado cargando y no puedo agregar',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await montarNotas(tester, repo: NotaPersonaRepositorioCargando());

        expect(find.bySemanticsLabel('Cargando las notas'), findsOneWidget);
        expect(find.text('+ Nueva nota'), findsNothing);
        expect(find.text('Notas de María'), findsOneWidget);
        semantica.dispose();
      },
    );

    testWidgets(
      'dado que leer las notas falla, cuando toco «Reintentar», se leen de nuevo y aparecen',
      (tester) async {
        final repo = NotaPersonaRepositorioQueFallaUnaVez(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);

        expect(find.text('No pudimos leer las notas de María en tu teléfono.'), findsOneWidget);
        expect(find.text('+ Nueva nota'), findsNothing);

        await tester.tap(find.text('Reintentar'));
        await asentar(tester);

        expect(find.text('No pudimos leer las notas de María en tu teléfono.'), findsNothing);
        expect(find.byKey(const ValueKey('nota_hoy')), findsOneWidget);
        expect(repo.lecturas, 2);
      },
    );

    testWidgets(
      'dado que leer a la persona falla, cuando miro, el aviso no nombra a nadie y guía con «Reintentar»',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso()..fallaDeContexto = const FailureInesperado();
        await montarNotas(tester, repo: repo);

        expect(find.text('No pudimos leer las notas en tu teléfono.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que la persona ya no está en el teléfono, cuando abro sus notas, el aviso dice qué hacer',
      (tester) async {
        await montarNotas(tester, repo: NotaPersonaRepositorioFalso()..contexto = null);

        expect(find.text('La persona ya no está en tu teléfono. Volvé atrás.'), findsOneWidget);
        expect(find.text('+ Nueva nota'), findsNothing);
      },
    );
  });

  group('solo lectura (persona o espacio dados de baja)', () {
    NotaPersonaRepositorioFalso soloLectura([
      ContextoNotasPersona contexto = const ContextoNotasPersona(
        nombre: 'María',
        causa: CausaSoloLectura.personaDeBaja,
      ),
    ]) => NotaPersonaRepositorioFalso(notas: notasDelCanvas(), contexto: contexto);

    const ayuda = 'Podés ver sus notas, pero no agregar, editar ni borrar ninguna.';

    testWidgets(
      'dado una persona en solo lectura, cuando abro sus notas, las veo con el aviso y sin agregar ni opciones',
      (tester) async {
        await montarNotas(tester, repo: soloLectura());

        expect(find.textContaining('María está de baja.'), findsOneWidget);
        expect(find.textContaining(ayuda), findsOneWidget);
        expect(find.text('+ Nueva nota'), findsNothing);
        expect(find.text('HOY 14:20'), findsOneWidget);

        await tester.tap(find.text('HOY 14:20'));
        await asentar(tester);
        expect(find.byKey(ClavesNotas.hojaOpciones), findsNothing);
      },
    );

    testWidgets(
      'dado una persona dada de baja el 22/10, cuando abro sus notas, el aviso dice desde cuándo (32B·04) y qué se puede hacer',
      (tester) async {
        final repo = soloLectura(
          ContextoNotasPersona(
            nombre: 'María',
            causa: CausaSoloLectura.personaDeBaja,
            bajaDesde: DateTime(2026, 10, 22, 9),
          ),
        );
        await montarNotas(tester, repo: repo);

        expect(find.text('María está de baja desde el 22/10. $ayuda'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que su depto está dado de baja, cuando abro sus notas, el aviso nombra el depto y la dirección (32B·08)',
      (tester) async {
        final repo = soloLectura(
          const ContextoNotasPersona(
            nombre: 'María',
            causa: CausaSoloLectura.espacioDeBaja,
            numeroDepto: '3B',
            direccion: 'Mataojo 2044',
          ),
        );
        await montarNotas(tester, repo: repo);

        expect(find.text('El depto 3B de Mataojo 2044 está dado de baja. $ayuda'), findsOneWidget);
      },
    );

    testWidgets(
      'dado un espacio dado de baja sin número ni dirección conocidos, cuando abro sus notas, el aviso igual dice la causa',
      (tester) async {
        final repo = soloLectura(
          const ContextoNotasPersona(nombre: 'María', causa: CausaSoloLectura.espacioDeBaja),
        );
        await montarNotas(tester, repo: repo);

        expect(find.text('El espacio de María está dado de baja. $ayuda'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que ya no está en ningún depto activo, cuando abro sus notas, el aviso lo dice',
      (tester) async {
        final repo = soloLectura(
          const ContextoNotasPersona(nombre: 'María', causa: CausaSoloLectura.sinEspacioActivo),
        );
        await montarNotas(tester, repo: repo);

        expect(find.text('María ya no está en ningún depto activo. $ayuda'), findsOneWidget);
      },
    );

    testWidgets(
      'dado una persona en solo lectura con notas borradas, cuando las miro, no hay «Restaurar»',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(
          notas: [notaDePrueba('b1', 'Borrada', borrada: DateTime(2026, 10, 22, 14, 30))],
          contexto: const ContextoNotasPersona(
            nombre: 'María',
            causa: CausaSoloLectura.personaDeBaja,
          ),
        );
        await montarNotas(tester, repo: repo);

        await tester.tap(find.text('Ver borradas (1)'));
        await asentar(tester);

        expect(find.text('Borrada'), findsOneWidget);
        expect(find.text('Restaurar'), findsNothing);
      },
    );

    testWidgets(
      'dado el texto al 200 % en un teléfono chico, cuando abro una persona en solo lectura, el aviso no tapa las notas',
      (tester) async {
        await montarNotas(tester, repo: soloLectura(), escala: 2, tamano: const Size(320, 568));

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('nota_hoy')), findsNothing);
        await tester.scrollUntilVisible(
          find.text('HOY 14:20'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('E·03 menú de una nota', () {
    testWidgets('dado una nota, cuando la toco, veo su hoja con «Editar», «Borrar» y «Cerrar»', (
      tester,
    ) async {
      await montarNotas(tester, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));

      await abrirOpciones(tester, 'hoy');

      expect(find.text('Nota de hoy 14:20'), findsOneWidget);
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Borrar'), findsOneWidget);
      expect(find.text('Cerrar'), findsOneWidget);
    });

    testWidgets(
      'dado una nota de otro día, cuando la toco, el título de la hoja dice «Nota del 05/10»',
      (tester) async {
        await montarNotas(tester, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));

        await abrirOpciones(tester, 'vieja');

        expect(find.text('Nota del 05/10'), findsOneWidget);
      },
    );

    testWidgets('dado la hoja abierta, cuando toco «Cerrar», no cambia nada', (tester) async {
      final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
      await montarNotas(tester, repo: repo);
      await abrirOpciones(tester, 'hoy');

      await tester.tap(find.text('Cerrar'));
      await asentar(tester);

      expect(find.byKey(ClavesNotas.hojaOpciones), findsNothing);
      expect(repo.llamadas, isEmpty);
      expect(find.byKey(const ValueKey('nota_hoy')), findsOneWidget);
    });

    testWidgets(
      'dado dos toques seguidos sobre la misma nota, cuando se abre su hoja, se abre una sola',
      (tester) async {
        await montarNotas(tester, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));

        await tester.tap(find.byKey(const ValueKey('nota_hoy')));
        await tester.tap(find.byKey(const ValueKey('nota_hoy')), warnIfMissed: false);
        await asentar(tester);

        expect(find.byKey(ClavesNotas.hojaOpciones), findsOneWidget);
      },
    );
  });

  group('E·04 borrar con «Deshacer»', () {
    testWidgets(
      'dado una nota, cuando la borro, sale de la lista, aparece «Nota borrada.» con «Deshacer» y «Ver borradas (1)»',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);

        await borrarPorMenu(tester, 'hoy');

        expect(find.byKey(const ValueKey('nota_hoy')), findsNothing);
        expect(find.byKey(const ValueKey('nota_vieja')), findsOneWidget);
        expect(find.text('Nota borrada.'), findsOneWidget);
        expect(find.text('Deshacer'), findsOneWidget);
        expect(find.text('Ver borradas (1)'), findsOneWidget);
        expect(repo.notas.firstWhere((n) => n.id == 'hoy').estaBorrada, isTrue);
        expect(repo.notas, hasLength(2), reason: 'borrar no pierde nada');
      },
    );

    testWidgets(
      'dado una nota borrada, cuando toco «Deshacer», vuelve a la lista y «Ver borradas» desaparece',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);
        await borrarPorMenu(tester, 'hoy');

        await tester.tap(find.text('Deshacer'));
        await asentar(tester);

        expect(find.byKey(const ValueKey('nota_hoy')), findsOneWidget);
        expect(find.textContaining('Ver borradas'), findsNothing);
        expect(repo.cuantas('restaurar'), 1);
      },
    );

    testWidgets(
      'dado dos toques seguidos sobre «Borrar», cuando se cierra la hoja, borra una vez y no cierra la pantalla',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);
        await abrirOpciones(tester, 'hoy');

        await tester.tap(find.byKey(ClavesNotas.botonBorrar));
        await tester.tap(find.byKey(ClavesNotas.botonBorrar), warnIfMissed: false);
        await asentar(tester);

        expect(repo.cuantas('borrar'), 1);
        expect(find.text('Notas de María'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que borrar falla, cuando miro, la nota sigue y el aviso ofrece «Reintentar», que funciona',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas())
          ..resultados['borrar'] = [const FailureInesperado()];
        await montarNotas(tester, repo: repo);

        await borrarPorMenu(tester, 'hoy');

        expect(find.text('No pudimos borrar la nota. Probá de nuevo.'), findsOneWidget);
        expect(find.byKey(const ValueKey('nota_hoy')), findsOneWidget);
        expect(find.text('Nota borrada.'), findsNothing);

        await tester.tap(find.text('Reintentar'));
        await asentar(tester);

        expect(find.text('Nota borrada.'), findsOneWidget);
        expect(find.byKey(const ValueKey('nota_hoy')), findsNothing);
        expect(repo.cuantas('borrar'), 2);
      },
    );

    testWidgets(
      'dado que borrar falló, cuando abro otra vez la hoja de esa nota, se puede borrar (nada queda trabado)',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas())
          ..resultados['borrar'] = [const FailureInesperado()];
        await montarNotas(tester, repo: repo);
        await borrarPorMenu(tester, 'hoy');

        await borrarPorMenu(tester, 'hoy');

        expect(find.text('Nota borrada.'), findsOneWidget);
        expect(repo.cuantas('borrar'), 2);
      },
    );

    testWidgets(
      'dado que borro una nota y, antes de que termine, borro otra, cuando terminan, las dos quedan borradas y el aviso es uno',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        repo.compuertas['borrar'] = Completer<void>();
        await montarNotas(tester, repo: repo);

        await borrarPorMenu(tester, 'hoy');
        await borrarPorMenu(tester, 'vieja');
        expect(repo.cuantas('borrar'), 2);

        repo.compuertas['borrar']!.complete();
        await asentar(tester);

        expect(find.text('Todavía no hay notas'), findsOneWidget);
        expect(find.text('Ver borradas (2)'), findsOneWidget);
        expect(find.text('Nota borrada.'), findsOneWidget);
      },
    );

    testWidgets(
      'dado un borrado en vuelo, cuando vuelvo atrás antes de que termine, el aviso con «Deshacer» sigue y deshace',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        repo.compuertas['borrar'] = Completer<void>();
        await montarNotas(tester, repo: repo);
        await borrarPorMenu(tester, 'hoy');

        await tester.tap(find.byTooltip('Volver'));
        await asentar(tester);
        repo.compuertas['borrar']!.complete();
        await asentar(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Nota borrada.'), findsOneWidget);
        repo.compuertas.remove('borrar');
        await tester.tap(find.text('Deshacer'));
        await asentar(tester);
        expect(repo.cuantas('restaurar'), 1);
        expect(repo.notas.firstWhere((n) => n.id == 'hoy').estaBorrada, isFalse);
      },
    );

    testWidgets(
      'dado que «Deshacer» falla, cuando lo toco, el aviso dice dónde está la nota y «Reintentar» la restaura',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas())
          ..resultados['restaurar'] = [const FailureInesperado()];
        await montarNotas(tester, repo: repo);
        await borrarPorMenu(tester, 'hoy');

        await tester.tap(find.text('Deshacer'));
        await asentar(tester);

        expect(find.textContaining('La nota sigue en «Ver borradas»'), findsOneWidget);
        expect(find.byKey(const ValueKey('nota_hoy')), findsNothing);

        await tester.tap(find.text('Reintentar'));
        await asentar(tester);

        expect(find.byKey(const ValueKey('nota_hoy')), findsOneWidget);
      },
    );

    testWidgets(
      'dado que no hay lector de pantalla, cuando pasan los 8 segundos, el aviso se va y la nota sigue en «Ver borradas»',
      (tester) async {
        await montarNotas(tester, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));
        await borrarPorMenu(tester, 'hoy');

        await tester.pump(const Duration(seconds: 12));
        await asentar(tester);

        expect(find.text('Nota borrada.'), findsNothing);
        expect(find.text('Ver borradas (1)'), findsOneWidget);
      },
    );

    testWidgets(
      'dado un lector de pantalla, cuando borro una nota, el aviso con «Deshacer» no se cierra solo',
      (tester) async {
        await montarNotas(
          tester,
          repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()),
          lector: true,
        );
        await borrarPorMenu(tester, 'hoy');

        await tester.pump(const Duration(seconds: 30));

        expect(find.text('Nota borrada.'), findsOneWidget);
        expect(find.text('Deshacer'), findsOneWidget);
      },
    );
  });

  group('nueva nota y editar', () {
    testWidgets(
      'dado que toco «+ Nueva nota», cuando guardo, vuelvo a la lista con la nota y el aviso de guardada',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);

        await tester.tap(find.text('+ Nueva nota'));
        await asentar(tester);
        expect(find.text('Nueva nota'), findsOneWidget);
        await tester.enterText(
          find.byKey(ClavesNotas.campo),
          'Prefiere que la llamen antes de pasar.',
        );
        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);

        expect(find.text('Notas de María'), findsOneWidget);
        expect(find.text('Prefiere que la llamen antes de pasar.'), findsOneWidget);
        expect(find.text('Guardamos la nota en este teléfono.'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que toco «+ Nueva nota» dos veces seguidas, cuando se abre, se abre un solo formulario',
      (tester) async {
        await montarNotas(tester);

        await tester.tap(find.text('+ Nueva nota'));
        await tester.tap(find.text('+ Nueva nota'), warnIfMissed: false);
        await asentar(tester);

        await tester.tap(find.byTooltip('Cerrar'));
        await asentar(tester);
        expect(find.text('Notas de María'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que elijo «Editar», cuando cambio el texto y guardo, la lista muestra el texto nuevo y el aviso de cambios',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);

        await abrirOpciones(tester, 'vieja');
        await elegirOpcion(tester, ClavesNotas.botonEditar);
        expect(find.text('Editar nota'), findsOneWidget);
        await tester.enterText(find.byKey(ClavesNotas.campo), 'Ahora trabaja de 10 a 14.');
        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);

        expect(find.text('Ahora trabaja de 10 a 14.'), findsOneWidget);
        expect(find.text('Trabaja en la farmacia de Av. Italia de 9 a 13.'), findsNothing);
        expect(find.text('Cambios guardados en tu teléfono.'), findsOneWidget);
        expect(find.text('05/10'), findsOneWidget, reason: 'created_at no cambia');
      },
    );

    testWidgets('dado que edito y cierro sin guardar, cuando vuelvo, la nota sigue como estaba', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
      await montarNotas(tester, repo: repo);
      await abrirOpciones(tester, 'vieja');
      await elegirOpcion(tester, ClavesNotas.botonEditar);
      await tester.enterText(find.byKey(ClavesNotas.campo), 'Cambio que no se guarda');

      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);
      await tester.tap(find.text('Descartar'));
      await asentar(tester);

      expect(find.text('Trabaja en la farmacia de Av. Italia de 9 a 13.'), findsOneWidget);
      expect(repo.llamadas, isEmpty);
    });

    testWidgets(
      'dado un borrado reciente, cuando edito otra nota, se aplican las dos y el aviso viejo no tapa el botón',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);

        await borrarPorMenu(tester, 'hoy');
        await abrirOpciones(tester, 'vieja');
        await elegirOpcion(tester, ClavesNotas.botonEditar);
        expect(find.text('Nota borrada.'), findsNothing);
        await tester.enterText(find.byKey(ClavesNotas.campo), 'Otra');
        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);

        expect(repo.cuantas('borrar'), 1);
        expect(repo.cuantas('editar'), 1);
        expect(repo.notas.firstWhere((n) => n.id == 'hoy').estaBorrada, isTrue);
        expect(repo.notas.firstWhere((n) => n.id == 'vieja').texto, 'Otra');
      },
    );
  });

  group('E·05 borradas', () {
    NotaPersonaRepositorioFalso conUnaBorrada() => NotaPersonaRepositorioFalso(
      notas: [
        notaDePrueba(
          'b1',
          'Pidió volver el sábado con el esposo.',
          borrada: DateTime(2026, 10, 22, 14, 30),
        ),
        notaDePrueba('vieja', 'Trabaja en la farmacia.', creada: DateTime(2026, 10, 5, 9)),
      ],
    );

    testWidgets(
      'dado una nota borrada, cuando toco «Ver borradas», veo «BORRADAS» con la nota atenuada y «Restaurar», sin agregar',
      (tester) async {
        await montarNotas(tester, repo: conUnaBorrada());

        await tester.tap(find.text('Ver borradas (1)'));
        await asentar(tester);

        expect(find.text('BORRADAS'), findsOneWidget);
        expect(find.text('Notas de María'), findsOneWidget);
        expect(find.text(privacidad), findsOneWidget);
        expect(find.text('Pidió volver el sábado con el esposo.'), findsOneWidget);
        expect(find.text('Trabaja en la farmacia.'), findsNothing);
        expect(find.text('Restaurar'), findsOneWidget);
        expect(find.text('+ Nueva nota'), findsNothing);
      },
    );

    testWidgets(
      'dado una nota borrada, cuando toco «Restaurar», aparece «Nota restaurada.» y vuelve a la lista con su fecha',
      (tester) async {
        final repo = conUnaBorrada();
        await montarNotas(tester, repo: repo);
        await tester.tap(find.text('Ver borradas (1)'));
        await asentar(tester);

        await tester.tap(find.text('Restaurar'));
        await asentar(tester);

        expect(find.text('Nota restaurada.'), findsOneWidget);
        expect(find.text('No hay notas borradas.'), findsOneWidget);
        await tester.tap(find.byTooltip('Volver'));
        await asentar(tester);
        expect(find.text('HOY 14:20'), findsOneWidget);
        expect(find.textContaining('Ver borradas'), findsNothing);
      },
    );

    testWidgets('dado dos toques seguidos sobre «Restaurar», cuando se procesa, restaura una vez', (
      tester,
    ) async {
      final repo = conUnaBorrada();
      repo.compuertas['restaurar'] = Completer<void>();
      await montarNotas(tester, repo: repo);
      await tester.tap(find.text('Ver borradas (1)'));
      await asentar(tester);

      await tester.tap(find.text('Restaurar'));
      await tester.tap(find.text('Restaurar'), warnIfMissed: false);
      await asentar(tester);
      repo.compuertas['restaurar']!.complete();
      await asentar(tester);

      expect(repo.cuantas('restaurar'), 1);
    });

    testWidgets(
      'dado que restaurar falla, cuando miro, la nota sigue borrada y el aviso ofrece «Reintentar»',
      (tester) async {
        final repo = conUnaBorrada()..resultados['restaurar'] = [const FailureInesperado()];
        await montarNotas(tester, repo: repo);
        await tester.tap(find.text('Ver borradas (1)'));
        await asentar(tester);

        await tester.tap(find.text('Restaurar'));
        await asentar(tester);

        expect(find.text('No pudimos restaurar la nota. Probá de nuevo.'), findsOneWidget);
        expect(find.text('Pidió volver el sábado con el esposo.'), findsOneWidget);

        await tester.tap(find.text('Reintentar'));
        await asentar(tester);

        expect(find.text('Nota restaurada.'), findsOneWidget);
        expect(repo.cuantas('restaurar'), 2);
      },
    );

    testWidgets(
      'dado el texto al 200 % en un teléfono chico, cuando veo las borradas, nada se desborda',
      (tester) async {
        await montarNotas(tester, repo: conUnaBorrada(), escala: 2, tamano: const Size(320, 568));
        await tester.scrollUntilVisible(
          find.text('Ver borradas (1)'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Ver borradas (1)'));
        await asentar(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Restaurar'), findsOneWidget);
      },
    );
  });
}

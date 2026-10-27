// La pestaña Notas de la hoja arriba de la casa (vista 39, C·05; HU-UBI-003): lista por fecha, «+ Nota
// del lugar», opciones, borrar con «Deshacer», «Ver borradas», y los estados de cargando, vacío, error
// de lectura y solo lectura, con los casos límite de cada flujo.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_notas_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_ubicacion_falsos.dart';
import 'notas_lugar_arnes.dart';

void main() {
  const privacidad = 'Estas notas viven solo en tu celular.';

  group('C·05 notas del lugar', () {
    testWidgets(
      'dado un lugar con dos notas, cuando abro la pestaña, veo el aviso, las notas de la más nueva a la más vieja con su fecha y «+ Nota del lugar»',
      (tester) async {
        await montarPestanaLugar(
          tester,
          repo: NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas()),
        );

        expect(find.text(privacidad), findsOneWidget);
        expect(find.text('+ Nota del lugar'), findsOneWidget);
        expect(find.text('HOY 14:20'), findsOneWidget);
        expect(find.text('05/10'), findsOneWidget);
        expect(find.text('El portón verde no cierra: tocar fuerte.'), findsOneWidget);
        expect(find.text('✎'), findsNWidgets(2), reason: 'cada nota lleva su lápiz');
        expect(find.textContaining('Ver borradas'), findsNothing);
        final arriba = tester.getTopLeft(find.byKey(ClavesNotasDelLugar.nota('hoy'))).dy;
        final abajo = tester.getTopLeft(find.byKey(ClavesNotasDelLugar.nota('vieja'))).dy;
        expect(arriba, lessThan(abajo));
        // El enlace va debajo de la última nota (canvas) y tiene un objetivo táctil de 48 dp.
        expect(tester.getTopLeft(find.text('+ Nota del lugar')).dy, greaterThan(abajo));
        expect(
          tester.getSize(find.byKey(ClavesNotasDelLugar.nueva)).height,
          greaterThanOrEqualTo(48),
        );
      },
    );

    testWidgets('dado una nota, cuando la miro, mide al menos 56 dp de alto y es un solo toque', (
      tester,
    ) async {
      await montarPestanaLugar(
        tester,
        repo: NotaUbicacionRepositorioFalso(notas: [notaDeLugar('a', 'Corta')]),
      );

      expect(
        tester.getSize(find.byKey(ClavesNotasDelLugar.nota('a'))).height,
        greaterThanOrEqualTo(56),
      );
    });

    testWidgets('dado que el aviso se esconde con «No volver a mostrar», la pestaña sigue igual', (
      tester,
    ) async {
      await montarPestanaLugar(
        tester,
        repo: NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas()),
      );
      expect(find.text('No volver a mostrar'), findsOneWidget);

      await tester.tap(find.text('No volver a mostrar'));
      await asentarLugar(tester);

      expect(find.text(privacidad), findsNothing);
      expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsOneWidget);
      expect(find.text('+ Nota del lugar'), findsOneWidget);
    });

    testWidgets(
      'dado que no hay un colportor con sesión, cuando abro la pestaña, el aviso no ofrece esconderse y no se escribe',
      (tester) async {
        await montarPestanaLugar(
          tester,
          colportorId: null,
          repo: NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas()),
        );

        expect(find.text(privacidad), findsOneWidget);
        expect(find.text('No volver a mostrar'), findsNothing);
        expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsOneWidget);
        expect(find.text('+ Nota del lugar'), findsNothing);
      },
    );

    testWidgets('dado el texto al 200 % en un teléfono chico, nada se desborda y se llega a todo', (
      tester,
    ) async {
      final muchas = [
        for (var i = 0; i < 12; i++)
          notaDeLugar(
            'n$i',
            'Nota larga número $i ${'con mucho texto ' * 12}',
            creada: DateTime(2026, 9, 1).add(Duration(days: i)),
          ),
      ];
      await montarPestanaLugar(
        tester,
        repo: NotaUbicacionRepositorioFalso(notas: muchas),
        escala: 2,
        tamano: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('+ Nota del lugar'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('+ Nota del lugar'), findsOneWidget);
    });

    testWidgets('dado una nota de 5000 caracteres, cuando la veo, se muestra entera', (
      tester,
    ) async {
      final larga = ('Línea de prueba. ' * 300).trim();
      await montarPestanaLugar(
        tester,
        repo: NotaUbicacionRepositorioFalso(notas: [notaDeLugar('larga', larga)]),
      );

      expect(find.text(larga), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado 60 notas, cuando bajo, la última se alcanza', (tester) async {
      final muchas = [
        for (var i = 0; i < 60; i++)
          notaDeLugar('n$i', 'Nota $i', creada: DateTime(2026, 8, 1).add(Duration(days: i))),
      ];
      await montarPestanaLugar(tester, repo: NotaUbicacionRepositorioFalso(notas: muchas));

      await tester.scrollUntilVisible(
        find.text('+ Nota del lugar'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('+ Nota del lugar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'dado las notas, cuando las lee el lector de pantalla, cada una dice su fecha y su texto y se puede tocar',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await montarPestanaLugar(
          tester,
          repo: NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas()),
        );

        const etiqueta = 'hoy a las 14:20. El portón verde no cierra: tocar fuerte.';
        expect(find.bySemanticsLabel(etiqueta), findsOneWidget);
        final nodo = tester.getSemantics(find.bySemanticsLabel(etiqueta));
        // ignore: deprecated_member_use
        expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      },
    );
  });

  group('estados', () {
    testWidgets('dado que las notas se están leyendo, cuando abro la pestaña, veo que carga', (
      tester,
    ) async {
      await montarPestanaLugar(tester, repo: NotaUbicacionRepositorioCargando());

      expect(find.byType(CargandoNotas), findsOneWidget);
      expect(find.text(privacidad), findsOneWidget);
    });

    testWidgets(
      'dado un lugar sin notas, cuando abro la pestaña, veo el vacío y «+ Nota del lugar»',
      (tester) async {
        await montarPestanaLugar(tester);

        expect(find.byKey(ClavesNotasDelLugar.vacio), findsOneWidget);
        expect(find.text('Todavía no hay notas'), findsOneWidget);
        expect(find.text('+ Nota del lugar'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que no se pudo leer, cuando toco «Reintentar», vuelve a leer y muestra las notas',
      (tester) async {
        final repo = NotaUbicacionRepositorioQueFallaUnaVez(notas: notasDelLugarDelCanvas());
        await montarPestanaLugar(tester, repo: repo);

        expect(find.byKey(ClavesNotasDelLugar.error), findsOneWidget);
        expect(find.text('No pudimos leer las notas del lugar en tu teléfono.'), findsOneWidget);
        expect(find.text('+ Nota del lugar'), findsNothing);

        await tester.tap(find.text('Reintentar'));
        await asentarLugar(tester);

        expect(find.byKey(ClavesNotasDelLugar.error), findsNothing);
        expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsOneWidget);
        expect(repo.lecturas, 2);
      },
    );

    testWidgets(
      'dado un lugar dado de baja, cuando abro la pestaña, veo las notas pero no se agregan, editan ni borran',
      (tester) async {
        await montarPestanaLugar(
          tester,
          soloLectura: true,
          repo: NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas()),
        );

        expect(find.byKey(ClavesNotasDelLugar.soloLectura), findsOneWidget);
        expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsOneWidget);
        expect(find.text('+ Nota del lugar'), findsNothing);

        await tester.tap(find.byKey(ClavesNotasDelLugar.nota('hoy')));
        await asentarLugar(tester);

        expect(find.byKey(ClavesNotas.hojaOpciones), findsNothing);
      },
    );

    testWidgets(
      'dado un lugar dado de baja con notas borradas, «Ver borradas» no ofrece «Restaurar»',
      (tester) async {
        await montarPestanaLugar(
          tester,
          soloLectura: true,
          repo: NotaUbicacionRepositorioFalso(
            notas: [notaDeLugar('b', 'Borrada', borrada: DateTime(2026, 10, 20))],
          ),
        );

        await tester.tap(find.text('Ver borradas (1)'));
        await asentarLugar(tester);

        expect(find.text('Borrada'), findsOneWidget);
        expect(find.text('Restaurar'), findsNothing);
      },
    );
  });

  group('agregar una nota', () {
    testWidgets(
      'dado que toco «+ Nota del lugar» y guardo, la nota aparece arriba con la fecha de hoy y un aviso la confirma',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas());
        await montarPestanaLugar(tester, repo: repo);

        await tester.tap(find.text('+ Nota del lugar'));
        await asentarLugar(tester);
        expect(find.text('Nueva nota'), findsOneWidget);
        await escribirYGuardarLugar(tester, '  Timbre roto, golpear la puerta.  ');

        expect(repo.textosRecibidos, ['Timbre roto, golpear la puerta.']);
        expect(find.text('Guardar nota'), findsNothing);
        expect(find.text('Timbre roto, golpear la puerta.'), findsOneWidget);
        expect(find.byKey(ClavesNotasDelLugar.aviso), findsOneWidget);
        expect(find.text('Guardamos la nota en este teléfono.'), findsOneWidget);
        expect(repo.notas.first.auditoria.createdBy, 'col-1');
        expect(repo.notas.first.ubicacionId, 'ubi-1');
      },
    );

    testWidgets('dado un doble toque en «+ Nota del lugar», se abre un solo formulario', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final rutas = ContadorDeRutas();
      await montarPestanaLugar(tester, observadores: [rutas]);

      // Por semántica: dos acciones seguidas antes de dibujar, sin que la ruta nueva tape la primera.
      final enlace = find.semantics.byLabel('+ Nota del lugar');
      tester.semantics.performAction(enlace, SemanticsAction.tap);
      tester.semantics.performAction(enlace, SemanticsAction.tap);
      await asentarLugar(tester);

      expect(rutas.empujadas, 1);
      expect(find.text('Guardar nota'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets(
      'dado que guardar falla, el texto queda, el botón vuelve a habilitarse y reintentar guarda una sola nota',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso()
          ..resultados['agregar'] = [const FailureInesperado(causa: 'x')];
        await montarPestanaLugar(tester, repo: repo);
        await tester.tap(find.text('+ Nota del lugar'));
        await asentarLugar(tester);

        await escribirYGuardarLugar(tester, 'Casa de esquina');

        expect(find.text('No pudimos guardar la nota. El texto sigue acá.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
          'Casa de esquina',
        );

        await tester.tap(find.text('Reintentar'));
        await asentarLugar(tester);

        expect(find.text('Guardar nota'), findsNothing);
        expect(repo.notas, hasLength(1));
        expect(repo.llamadas, ['agregar:lugar-nueva-1', 'agregar:lugar-nueva-1']);
      },
    );

    testWidgets('dado que el lugar se dio de baja mientras escribía, el formulario dice por qué', (
      tester,
    ) async {
      final repo = NotaUbicacionRepositorioFalso()
        ..resultados['agregar'] = [
          const FailureValidacion(campos: {'ubicacion': 'Este lugar está dado de baja.'}),
        ];
      await montarPestanaLugar(tester, repo: repo);
      await tester.tap(find.text('+ Nota del lugar'));
      await asentarLugar(tester);

      await escribirYGuardarLugar(tester, 'Algo');

      expect(find.text('Este lugar está dado de baja.'), findsOneWidget);
      expect(repo.notas, isEmpty);
    });
  });

  group('editar y borrar', () {
    testWidgets(
      'dado que edito una nota, cuando guardo, la lista muestra el texto nuevo y no otra nota',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas());
        await montarPestanaLugar(tester, repo: repo);

        await abrirOpcionesLugar(tester, 'hoy');
        expect(find.text('Nota de hoy 14:20'), findsOneWidget);
        await tester.tap(find.byKey(ClavesNotas.botonEditar));
        await asentarLugar(tester);
        expect(find.text('Editar nota'), findsOneWidget);
        await escribirYGuardarLugar(tester, 'El portón ya cierra.');

        expect(find.text('El portón ya cierra.'), findsOneWidget);
        expect(find.text('El portón verde no cierra: tocar fuerte.'), findsNothing);
        expect(find.text('Cambios guardados en tu teléfono.'), findsOneWidget);
        expect(repo.notas, hasLength(2));
      },
    );

    testWidgets('dado que borro una nota, sale de la lista y el aviso ofrece «Deshacer»', (
      tester,
    ) async {
      final repo = NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas());
      await montarPestanaLugar(tester, repo: repo);

      await borrarPorMenuLugar(tester, 'hoy');

      expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsNothing);
      expect(find.text('Nota borrada.'), findsOneWidget);
      expect(find.byKey(ClavesNotasDelLugar.deshacer), findsOneWidget);
      expect(find.text('Ver borradas (1)'), findsOneWidget);
      expect(
        repo.notas.firstWhere((n) => n.id == 'hoy').estaBorrada,
        isTrue,
        reason: 'no se pierde',
      );
    });

    testWidgets('dado que borré una nota, cuando toco «Deshacer», vuelve a su lugar', (
      tester,
    ) async {
      final repo = NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas());
      await montarPestanaLugar(tester, repo: repo);
      await borrarPorMenuLugar(tester, 'hoy');

      await tester.tap(find.byKey(ClavesNotasDelLugar.deshacer));
      await asentarLugar(tester);

      expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsOneWidget);
      expect(find.text('Nota restaurada.'), findsOneWidget);
      expect(find.textContaining('Ver borradas'), findsNothing);
    });

    testWidgets('dado un doble toque en «Deshacer», se restaura una sola vez', (tester) async {
      final repo = NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas());
      await montarPestanaLugar(tester, repo: repo);
      await borrarPorMenuLugar(tester, 'hoy');
      repo.compuertas['restaurar'] = Completer<void>();

      await tester.tap(find.byKey(ClavesNotasDelLugar.deshacer));
      await tester.tap(find.byKey(ClavesNotasDelLugar.deshacer), warnIfMissed: false);
      await tester.pump();
      repo.compuertas['restaurar']!.complete();
      await asentarLugar(tester);

      expect(repo.cuantas('restaurar'), 1);
      expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsOneWidget);
    });

    testWidgets(
      'dado que borro una nota y enseguida otra, las dos quedan borradas y el aviso es el de la última',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas());
        await montarPestanaLugar(tester, repo: repo);

        await borrarPorMenuLugar(tester, 'hoy');
        await borrarPorMenuLugar(tester, 'vieja');

        expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsNothing);
        expect(find.byKey(ClavesNotasDelLugar.nota('vieja')), findsNothing);
        expect(find.text('Ver borradas (2)'), findsOneWidget);
        expect(find.text('Nota borrada.'), findsOneWidget);
        expect(repo.notas.every((n) => n.estaBorrada), isTrue);
      },
    );

    testWidgets(
      'dado que borro una nota y otra queda en vuelo, deshacer la primera no pisa el borrado de la segunda',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas());
        await montarPestanaLugar(tester, repo: repo);
        await borrarPorMenuLugar(tester, 'hoy');

        repo.compuertas['borrar'] = Completer<void>();
        await abrirOpcionesLugar(tester, 'vieja');
        await tester.tap(find.byKey(ClavesNotas.botonBorrar));
        await tester.pump();
        await tester.tap(find.byKey(ClavesNotasDelLugar.deshacer));
        await tester.pump();
        repo.compuertas['borrar']!.complete();
        await asentarLugar(tester);

        expect(repo.notas.firstWhere((n) => n.id == 'hoy').estaBorrada, isFalse);
        expect(repo.notas.firstWhere((n) => n.id == 'vieja').estaBorrada, isTrue);
        expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsOneWidget);
        expect(find.byKey(ClavesNotasDelLugar.nota('vieja')), findsNothing);
      },
    );

    testWidgets(
      'dado que borrar falla, la nota sigue en la lista, el aviso dice qué hacer y «Reintentar» la borra',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas())
          ..resultados['borrar'] = [const FailureInesperado(causa: 'x')];
        await montarPestanaLugar(tester, repo: repo);

        await borrarPorMenuLugar(tester, 'hoy');

        expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsOneWidget);
        expect(find.text('No pudimos borrar la nota. Probá de nuevo.'), findsOneWidget);

        await tester.tap(find.text('Reintentar'));
        await asentarLugar(tester);

        expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsNothing);
        expect(find.text('Nota borrada.'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que deshacer falla, el aviso manda a «Ver borradas» y «Reintentar» restaura',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso(notas: notasDelLugarDelCanvas())
          ..resultados['restaurar'] = [const FailureInesperado(causa: 'x')];
        await montarPestanaLugar(tester, repo: repo);
        await borrarPorMenuLugar(tester, 'hoy');

        await tester.tap(find.byKey(ClavesNotasDelLugar.deshacer));
        await asentarLugar(tester);

        expect(find.textContaining('podés restaurarla desde ahí'), findsOneWidget);
        expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsNothing);

        await tester.tap(find.text('Reintentar'));
        await asentarLugar(tester);

        expect(find.byKey(ClavesNotasDelLugar.nota('hoy')), findsOneWidget);
      },
    );
  });

  group('ver borradas', () {
    testWidgets(
      'dado dos notas borradas, cuando restauro una, vuelve a la lista y la otra sigue borrada',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso(
          notas: [
            notaDeLugar('a', 'Primera', borrada: DateTime(2026, 10, 20)),
            notaDeLugar(
              'b',
              'Segunda',
              borrada: DateTime(2026, 10, 21),
              creada: DateTime(2026, 10, 2),
            ),
          ],
        );
        await montarPestanaLugar(tester, repo: repo);
        expect(find.byKey(ClavesNotasDelLugar.nota('a')), findsNothing);

        await tester.tap(find.text('Ver borradas (2)'));
        await asentarLugar(tester);
        expect(find.text('BORRADAS'), findsOneWidget);
        await tester.tap(find.text('Restaurar').first);
        await asentarLugar(tester);

        expect(find.text('Nota restaurada.'), findsOneWidget);
        expect(find.text('Restaurar'), findsOneWidget);

        await tester.tap(find.byTooltip('Volver'));
        await asentarLugar(tester);

        expect(find.byKey(ClavesNotasDelLugar.nota('a')), findsOneWidget);
        expect(find.text('Ver borradas (1)'), findsOneWidget);
      },
    );

    testWidgets('dado que restaurar falla, la nota sigue borrada y se puede reintentar', (
      tester,
    ) async {
      final repo = NotaUbicacionRepositorioFalso(
        notas: [notaDeLugar('a', 'Primera', borrada: DateTime(2026, 10, 20))],
      )..resultados['restaurar'] = [const FailureInesperado(causa: 'x')];
      await montarPestanaLugar(tester, repo: repo);
      await tester.tap(find.text('Ver borradas (1)'));
      await asentarLugar(tester);

      await tester.tap(find.text('Restaurar'));
      await asentarLugar(tester);

      expect(find.text('No pudimos restaurar la nota. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Restaurar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await asentarLugar(tester);

      expect(find.text('Nota restaurada.'), findsOneWidget);
      expect(repo.cuantas('restaurar'), 2);
    });

    testWidgets('dado un doble toque en «Restaurar», se restaura una sola vez', (tester) async {
      final repo = NotaUbicacionRepositorioFalso(
        notas: [notaDeLugar('a', 'Primera', borrada: DateTime(2026, 10, 20))],
      );
      await montarPestanaLugar(tester, repo: repo);
      await tester.tap(find.text('Ver borradas (1)'));
      await asentarLugar(tester);
      repo.compuertas['restaurar'] = Completer<void>();

      await tester.tap(find.text('Restaurar'));
      await tester.tap(find.text('Restaurar'), warnIfMissed: false);
      await tester.pump();
      repo.compuertas['restaurar']!.complete();
      await asentarLugar(tester);

      expect(repo.cuantas('restaurar'), 1);
    });

    testWidgets('dado que salgo de «Ver borradas» y vuelvo a entrar, siguen todas', (tester) async {
      final repo = NotaUbicacionRepositorioFalso(
        notas: [notaDeLugar('a', 'Primera', borrada: DateTime(2026, 10, 20))],
      );
      await montarPestanaLugar(tester, repo: repo);

      await tester.tap(find.text('Ver borradas (1)'));
      await asentarLugar(tester);
      await tester.tap(find.byTooltip('Volver'));
      await asentarLugar(tester);
      await tester.tap(find.text('Ver borradas (1)'));
      await asentarLugar(tester);

      expect(find.text('Primera'), findsOneWidget);
    });
  });
}

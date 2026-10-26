// El formulario de una nota (HU-UBI-012, vista 32E): E·02 «Nueva nota», E·07 error al guardar y la
// edición de una nota existente.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_persona_falsos.dart';
import 'notas_persona_arnes.dart';

void main() {
  Future<void> escribir(WidgetTester tester, String texto) async {
    await tester.enterText(find.byKey(ClavesNotas.campo), texto);
    await tester.pump();
  }

  Future<void> guardar(WidgetTester tester) async {
    await tester.tap(find.text('Guardar nota'));
    await asentar(tester);
  }

  group('E·02 nueva nota', () {
    testWidgets(
      'dado que abro el formulario, cuando lo miro, veo el título, el aviso de privacidad, el campo con foco y el botón',
      (tester) async {
        await montarFormulario(tester);

        expect(find.text('Nueva nota'), findsOneWidget);
        expect(find.text('Estas notas viven solo en tu celular.'), findsOneWidget);
        expect(find.text('Guardar nota'), findsOneWidget);
        expect(find.byTooltip('Cerrar'), findsOneWidget);
        final campo = tester.widget<TextField>(find.byKey(ClavesNotas.campo));
        expect(campo.focusNode!.hasFocus, isTrue, reason: 'el campo se abre con el foco');
      },
    );

    testWidgets(
      'dado un texto con espacios de más, cuando guardo, se guarda recortado y devuelve la nota nueva',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        final resultado = await montarFormulario(tester, repo: repo);

        await escribir(tester, '  Prefiere de tarde.  \n');
        await guardar(tester);

        expect(repo.textosRecibidos, ['Prefiere de tarde.']);
        expect(resultado.cierres, 1);
        expect(resultado.guardada?.esNueva, isTrue);
        expect(resultado.guardada?.nota.texto, 'Prefiere de tarde.');
        expect(resultado.guardada?.nota.auditoria.createdBy, 'col-1');
        expect(find.text('Guardar nota'), findsNothing);
      },
    );

    testWidgets(
      'dado que la nota está en blanco, cuando toco «Guardar nota», no guarda, dice qué hacer y deja el foco en el campo',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        final resultado = await montarFormulario(tester, repo: repo);

        await escribir(tester, '   \n  ');
        await guardar(tester);

        expect(find.text('Escribí la nota para poder guardarla.'), findsOneWidget);
        expect(repo.llamadas, isEmpty);
        expect(resultado.cierres, 0);
        final campo = tester.widget<TextField>(find.byKey(ClavesNotas.campo));
        expect(campo.focusNode!.hasFocus, isTrue);
      },
    );

    testWidgets(
      'dado un error por la nota en blanco, cuando escribo, el error se va y se puede guardar',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        await montarFormulario(tester, repo: repo);
        await guardar(tester);
        expect(find.text('Escribí la nota para poder guardarla.'), findsOneWidget);

        await escribir(tester, 'Algo');
        expect(find.text('Escribí la nota para poder guardarla.'), findsNothing);
        await guardar(tester);

        expect(repo.cuantas('agregar'), 1);
      },
    );

    testWidgets(
      'dado un texto de más de 5000 caracteres, cuando lo escribo, avisa pero deja guardar entero',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        final resultado = await montarFormulario(tester, repo: repo);
        final largo = 'a' * 5200;

        await escribir(tester, largo);

        expect(find.textContaining('5200 caracteres'), findsOneWidget);
        expect(find.textContaining('Podés guardarla igual'), findsOneWidget);
        await guardar(tester);
        expect(repo.textosRecibidos.single, largo);
        expect(resultado.guardada?.nota.texto, largo);
      },
    );

    testWidgets('dado un texto de exactamente 5000 caracteres, cuando lo escribo, no avisa', (
      tester,
    ) async {
      await montarFormulario(tester);

      await escribir(tester, 'a' * 5000);

      expect(find.textContaining('Podés guardarla igual'), findsNothing);
    });

    testWidgets('dado que cierro con la ✕, cuando no guardé, vuelvo sin nota y sin tocar nada', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso();
      final resultado = await montarFormulario(tester, repo: repo);
      await escribir(tester, 'Algo que no se guarda');

      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);

      expect(resultado.cierres, 1);
      expect(resultado.guardada, isNull);
      expect(repo.llamadas, isEmpty);
    });

    testWidgets('dado que cerré y vuelvo a abrir el formulario, cuando lo miro, está vacío', (
      tester,
    ) async {
      final resultado = await montarFormulario(tester);
      await escribir(tester, 'Algo');
      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);

      await tester.tap(find.text('abrir formulario'));
      await asentar(tester);

      expect(resultado.cierres, 1);
      expect(tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text, isEmpty);
    });
  });

  group('doble toque y acciones seguidas', () {
    testWidgets(
      'dado dos toques seguidos sobre «Guardar nota», cuando el guardado está en curso, guarda una sola vez',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        repo.compuertas['agregar'] = Completer<void>();
        final resultado = await montarFormulario(tester, repo: repo);
        await escribir(tester, 'Una sola vez');

        await tester.tap(find.text('Guardar nota'));
        await tester.pump();
        expect(find.text('Guardando…'), findsOneWidget);
        await tester.tap(find.text('Guardando…'), warnIfMissed: false);
        await tester.pump();
        repo.compuertas['agregar']!.complete();
        await asentar(tester);

        expect(repo.cuantas('agregar'), 1);
        expect(repo.notas, hasLength(1));
        expect(resultado.cierres, 1);
      },
    );

    testWidgets(
      'dado un guardado en curso, cuando intento cerrar con la ✕ o con atrás, no se cierra hasta que termina',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        repo.compuertas['agregar'] = Completer<void>();
        final resultado = await montarFormulario(tester, repo: repo);
        await escribir(tester, 'Texto');
        await tester.tap(find.text('Guardar nota'));
        await tester.pump();

        await tester.tap(find.byTooltip('Cerrar'), warnIfMissed: false);
        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(resultado.cierres, 0);
        expect(find.text('Guardando…'), findsOneWidget);
        repo.compuertas['agregar']!.complete();
        await asentar(tester);
        expect(resultado.cierres, 1);
        expect(resultado.guardada?.nota.texto, 'Texto');
      },
    );

    testWidgets('dado un guardado en curso, cuando miro el campo, no se puede cambiar el texto', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso();
      repo.compuertas['agregar'] = Completer<void>();
      await montarFormulario(tester, repo: repo);
      await escribir(tester, 'Texto');
      await tester.tap(find.text('Guardar nota'));
      await tester.pump();

      expect(tester.widget<TextField>(find.byKey(ClavesNotas.campo)).readOnly, isTrue);
      repo.compuertas['agregar']!.complete();
      await asentar(tester);
    });
  });

  group('E·07 error al guardar', () {
    testWidgets(
      'dado que guardar falla, cuando termina, el texto sigue en el campo, el aviso dice qué pasó y el botón pasa a «Reintentar»',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso()
          ..resultados['agregar'] = [const FailureInesperado()];
        final resultado = await montarFormulario(tester, repo: repo);
        await escribir(tester, 'No se puede perder');

        await guardar(tester);

        expect(find.text('No pudimos guardar la nota. El texto sigue acá.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.text('Guardar nota'), findsNothing);
        expect(find.text('Guardando…'), findsNothing);
        expect(
          tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
          'No se puede perder',
        );
        expect(tester.widget<TextField>(find.byKey(ClavesNotas.campo)).readOnly, isFalse);
        expect(resultado.cierres, 0);
      },
    );

    testWidgets(
      'dado que guardar falló, cuando toco «Reintentar», guarda con el mismo id: una sola nota',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso()
          ..resultados['agregar'] = [const FailureInesperado()];
        final resultado = await montarFormulario(tester, repo: repo);
        await escribir(tester, 'Una nota');
        await guardar(tester);

        await tester.tap(find.text('Reintentar'));
        await asentar(tester);

        expect(repo.llamadas, ['agregar:nota-nueva-1', 'agregar:nota-nueva-1']);
        expect(repo.notas, hasLength(1));
        expect(resultado.cierres, 1);
        expect(resultado.guardada?.esNueva, isTrue);
      },
    );

    testWidgets(
      'dado que guardar falló, cuando cambio el texto y reintento, se guarda el texto nuevo',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso()
          ..resultados['agregar'] = [const FailureInesperado()];
        await montarFormulario(tester, repo: repo);
        await escribir(tester, 'Primero');
        await guardar(tester);

        await escribir(tester, 'Segundo');
        await tester.tap(find.text('Reintentar'));
        await asentar(tester);

        expect(repo.textosRecibidos, ['Primero', 'Segundo']);
      },
    );

    testWidgets(
      'dado que falla dos veces seguidas, cuando reintento, el botón sigue habilitado cada vez',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso()
          ..resultados['agregar'] = [const FailureInesperado(), const FailureInesperado()];
        final resultado = await montarFormulario(tester, repo: repo);
        await escribir(tester, 'Texto');
        await guardar(tester);

        await tester.tap(find.text('Reintentar'));
        await asentar(tester);
        expect(find.text('No pudimos guardar la nota. El texto sigue acá.'), findsOneWidget);
        expect(find.text('Guardando…'), findsNothing);

        await tester.tap(find.text('Reintentar'));
        await asentar(tester);
        expect(resultado.cierres, 1);
        expect(repo.cuantas('agregar'), 3);
      },
    );

    testWidgets(
      'dado que la persona pasó a solo lectura, cuando guardo, el aviso dice el motivo que dio la persistencia',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso()
          ..resultados['agregar'] = [
            const FailureValidacion(
              campos: {'persona': 'Esta persona está en solo lectura: no se pueden agregar notas.'},
            ),
          ];
        await montarFormulario(tester, repo: repo);
        await escribir(tester, 'Texto');

        await guardar(tester);

        expect(
          find.text('Esta persona está en solo lectura: no se pueden agregar notas.'),
          findsOneWidget,
        );
        expect(find.text('No pudimos guardar la nota. El texto sigue acá.'), findsNothing);
      },
    );
  });

  group('editar una nota', () {
    final original = notaDePrueba('n1', 'Texto original');

    testWidgets(
      'dado una nota, cuando abro «Editar», veo su texto, el título «Editar nota» y el aviso de privacidad',
      (tester) async {
        await montarFormulario(
          tester,
          repo: NotaPersonaRepositorioFalso(notas: [original]),
          nota: original,
        );

        expect(find.text('Editar nota'), findsOneWidget);
        expect(find.text('Estas notas viven solo en tu celular.'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
          'Texto original',
        );
      },
    );

    testWidgets(
      'dado que cambio el texto, cuando guardo, edita la nota y devuelve que no es nueva',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: [original]);
        final resultado = await montarFormulario(tester, repo: repo, nota: original);

        await escribir(tester, 'Texto corregido');
        await guardar(tester);

        expect(repo.llamadas, ['editar:n1']);
        expect(resultado.guardada?.esNueva, isFalse);
        expect(resultado.guardada?.nota.texto, 'Texto corregido');
        expect(repo.notas.single.auditoria.createdAt, original.auditoria.createdAt);
      },
    );

    testWidgets(
      'dado que no cambio nada, cuando guardo, vuelve sin escribir (updated_at no se toca)',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: [original]);
        final resultado = await montarFormulario(tester, repo: repo, nota: original);

        await guardar(tester);

        expect(repo.llamadas, isEmpty);
        expect(resultado.cierres, 1);
        expect(resultado.guardada, isNull);
      },
    );

    testWidgets('dado que borro todo el texto, cuando guardo, no vacía la nota: pide escribirla', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso(notas: [original]);
      await montarFormulario(tester, repo: repo, nota: original);

      await escribir(tester, '');
      await guardar(tester);

      expect(find.text('Escribí la nota para poder guardarla.'), findsOneWidget);
      expect(repo.llamadas, isEmpty);
    });

    testWidgets(
      'dado que editar falla, cuando termina, el texto editado sigue y «Reintentar» lo guarda',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: [original])
          ..resultados['editar'] = [const FailureInesperado()];
        final resultado = await montarFormulario(tester, repo: repo, nota: original);
        await escribir(tester, 'Texto corregido');
        await guardar(tester);

        expect(find.text('No pudimos guardar la nota. El texto sigue acá.'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller!.text,
          'Texto corregido',
        );
        await tester.tap(find.text('Reintentar'));
        await asentar(tester);

        expect(repo.cuantas('editar'), 2);
        expect(resultado.guardada?.nota.texto, 'Texto corregido');
      },
    );

    testWidgets('dado que la nota ya fue borrada, cuando guardo, el aviso dice el motivo', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso(notas: [original])
        ..resultados['editar'] = [
          const FailureValidacion(
            campos: {'nota': 'Esta nota está borrada: restauraila para editarla.'},
          ),
        ];
      await montarFormulario(tester, repo: repo, nota: original);
      await escribir(tester, 'Otro');

      await guardar(tester);

      expect(find.text('Esta nota está borrada: restauraila para editarla.'), findsOneWidget);
    });
  });

  group('tamaños y texto grande', () {
    testWidgets(
      'dado el texto al 200 % en un teléfono chico y una nota larga, cuando escribo, no se desborda y el botón se alcanza',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        final resultado = await montarFormulario(
          tester,
          repo: repo,
          escala: 2,
          tamano: const Size(320, 568),
        );

        await escribir(tester, 'Línea larga de prueba. ' * 120);

        expect(tester.takeException(), isNull);
        expect(find.text('Guardar nota'), findsOneWidget);
        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);
        expect(resultado.cierres, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'dado el texto al 200 %, cuando falla el guardado, el aviso rojo y el botón caben',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso()
          ..resultados['agregar'] = [const FailureInesperado()];
        await montarFormulario(tester, repo: repo, escala: 2, tamano: const Size(320, 568));
        await escribir(tester, 'Texto');

        await guardar(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Reintentar'), findsOneWidget);
      },
    );

    testWidgets(
      'dado un lector de pantalla, cuando miro el campo y el botón, tienen etiqueta y tamaño de toque suficientes',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await montarFormulario(tester);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(tester.getSemantics(find.byKey(ClavesNotas.campo)).label, contains('Nota'));
        semantica.dispose();
      },
    );
  });
}

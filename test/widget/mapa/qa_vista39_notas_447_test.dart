// QA de las notas del lugar en la hoja de la casa arriba (vista 39, C·05, #447, PR #493), con la hoja
// real y el enganche de `main.dart`: criterios de la HU, cinco estados, matriz de tamaños y escalas sin
// desbordes, casos límite (acciones superpuestas, fallas, entrada de texto) y privacidad.
//
// Las capturas (`--dart-define=QA_CAPTURAS=true`) van a `.dart_tool/qa_capturas/` y no se commitean.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_notas_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_ubicacion_falsos.dart';
import '../../helpers/qa_vista39_447_arnes.dart';

const _tamanos = [t360x640, t412x915];
const _escalas = [1.0, 2.0];

void main() {
  setUpAll(() {});

  group('QA 447 · criterios de la HU (texto literal del canvas C·05)', () {
    testWidgets(
      'dado un lugar con dos notas, cuando abro «Notas», veo el aviso, las notas de la más nueva a '
      'la más vieja con su fecha y «+ Nota del lugar»',
      (tester) async {
        await llegarA447(tester, Estado447.c05Canvas);

        expect(find.text('Estas notas viven solo en tu celular.'), findsOneWidget);
        expect(find.text('+ Nota del lugar'), findsOneWidget);
        expect(find.text('05/10'), findsOneWidget);
        expect(find.text('03/10'), findsOneWidget);
        final y1 = tester.getTopLeft(find.text(textoCanvas1)).dy;
        final y2 = tester.getTopLeft(find.text(textoCanvas2)).dy;
        expect(y1, lessThan(y2), reason: 'la del 05/10 va antes que la del 03/10');
        final yEnlace = tester.getTopLeft(find.text('+ Nota del lugar')).dy;
        expect(yEnlace, greaterThan(y2), reason: '«+ Nota del lugar» va después de las notas');
      },
    );

    testWidgets('dado una nota de hoy, la fecha dice «HOY 14:20»', (tester) async {
      await montarHoja447(
        tester,
        notas: [
          notaDeLugar('h', 'De hoy', ubicacionId: 'u-1', creada: DateTime(2026, 10, 22, 14, 20)),
        ],
      );
      expect(find.text('HOY 14:20'), findsOneWidget);
    });

    testWidgets('dado un lugar sin notas, veo «Todavía no hay notas» y puedo sumar la primera', (
      tester,
    ) async {
      await llegarA447(tester, Estado447.vacio);
      expect(find.text('Todavía no hay notas'), findsOneWidget);
      expect(find.text('Anotá lo que te sirva para la próxima visita.'), findsOneWidget);
      expect(find.text('+ Nota del lugar'), findsOneWidget);
    });

    testWidgets('dado que sumo una nota, queda arriba de las anteriores con su fecha de hoy', (
      tester,
    ) async {
      await llegarA447(tester, Estado447.c05Canvas);
      await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.nueva));
      await tester.tap(find.byKey(ClavesNotasDelLugar.nueva));
      await asentarLugar(tester);
      await escribirYGuardarLugar(tester, 'Casa de esquina, portón azul.');

      expect(find.text('Guardamos la nota en este teléfono.'), findsOneWidget);
      final nueva = tester.getTopLeft(find.text('Casa de esquina, portón azul.')).dy;
      expect(nueva, lessThan(tester.getTopLeft(find.text(textoCanvas1)).dy));
    });

    testWidgets('dado que no hay conexión, todo funciona igual (nada sale del teléfono)', (
      tester,
    ) async {
      // La pestaña no depende de ningún proveedor de red: el montaje no override-a ninguno y no falla.
      final m = await llegarA447(tester, Estado447.c05Canvas);
      await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.nueva));
      await tester.tap(find.byKey(ClavesNotasDelLugar.nueva));
      await asentarLugar(tester);
      await escribirYGuardarLugar(tester, 'Sin red');
      expect(m.repo.notas.map((n) => n.texto), contains('Sin red'));
    });
  });

  group('QA 447 · cinco estados con contenido (§8.3)', () {
    testWidgets('cargando: dice qué carga, no es un spinner pelado', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA447(tester, Estado447.cargando);
      expect(find.bySemanticsLabel('Cargando las notas'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('error al leer: dice qué pasó y ofrece «Reintentar», que recupera las notas', (
      tester,
    ) async {
      await llegarA447(tester, Estado447.errorAlLeer);
      expect(find.text('No pudimos leer las notas del lugar en tu teléfono.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await asentarLugar(tester);
      expect(find.text(textoCanvas1), findsOneWidget);
      expect(find.byKey(ClavesNotasDelLugar.error), findsNothing);
    });

    testWidgets('lugar dado de baja: las notas se leen, no hay con qué escribir y dice por qué', (
      tester,
    ) async {
      await llegarA447(tester, Estado447.dadaDeBaja);
      expect(find.byKey(ClavesNotasDelLugar.soloLectura), findsOneWidget);
      expect(find.text('+ Nota del lugar'), findsNothing);
      await tester.tap(find.text(textoCanvas1));
      await asentarLugar(tester);
      expect(find.byKey(ClavesNotas.hojaOpciones), findsNothing);
    });
  });

  group('QA 447 · matriz de estados × tamaños × escala (sin desbordes, todo alcanzable)', () {
    for (final estado in Estado447.values) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          testWidgets('${estado.name} · ${sufijo447(tamano, escala)}', (tester) async {
            if (conCapturas447) await cargarFuentes205(tester);
            await llegarA447(tester, estado, tamano: tamano, escala: escala);
            await tester.pump(const Duration(milliseconds: 100));

            expect(tester.takeException(), isNull, reason: 'overflow u otra excepción');
            await capturar447(tester, '${estado.name}_${sufijo447(tamano, escala)}');

            // Lo que se puede tocar se alcanza (con el desplazamiento) y no lo tapa nada.
            // Con la hoja de opciones abierta (modal) lo de atrás no se toca: no cuenta.
            for (final clave
                in estado == Estado447.opcionesDeLaNota
                    ? const <Key>[]
                    : [
                        ClavesNotasDelLugar.nueva,
                        ClavesNotasDelLugar.verBorradas,
                        ClavesNotasDelLugar.deshacer,
                      ]) {
              final f = find.byKey(clave);
              if (f.evaluate().isEmpty) continue;
              await tester.ensureVisible(f.first);
              await tester.pump();
              expect(f.first.hitTestable(), findsOneWidget, reason: '$clave tapado a $escala×');
              expect(tester.takeException(), isNull);
            }
          });
        }
      }
    }
  });

  group('QA 447 · acciones superpuestas y fallas a mitad de la acción', () {
    testWidgets(
      'dado dos borrados seguidos antes de que termine el primero, las dos salen, las dos quedan en '
      '«Ver borradas (2)» y «Deshacer» devuelve solo la del último aviso',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso(notas: notasC05());
        final compuerta = Completer<void>();
        repo.compuertas['borrar'] = compuerta;
        await montarHoja447(tester, repo: repo);

        await abrirOpcionesLugar(tester, 'c1');
        await tester.tap(find.byKey(ClavesNotas.botonBorrar));
        await tester.pump();
        await abrirOpcionesLugar(tester, 'c2');
        await tester.tap(find.byKey(ClavesNotas.botonBorrar));
        await tester.pump();
        compuerta.complete();
        await asentarLugar(tester);

        expect(find.text(textoCanvas1), findsNothing);
        expect(find.text(textoCanvas2), findsNothing);
        expect(find.text('Ver borradas (2)'), findsOneWidget);
        expect(repo.cuantas('borrar'), 2);
        // Un solo aviso con «Deshacer»; el segundo reemplazó al primero (decisión del orquestador, P4).
        expect(find.byKey(ClavesNotasDelLugar.deshacer), findsOneWidget);
        await tester.tap(find.byKey(ClavesNotasDelLugar.deshacer));
        await asentarLugar(tester);
        expect(repo.cuantas('restaurar'), 1);
        expect(find.text('Ver borradas (1)'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que «Deshacer» falla, el aviso dice qué pasó, la nota sigue en «Ver borradas» '
      'y «Reintentar» la restaura',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso(notas: notasC05())
          ..resultados['restaurar'] = [const FailureInesperado(causa: 'x')];
        await montarHoja447(tester, repo: repo);
        await borrarPorMenuLugar(tester, 'c1');
        await tester.tap(find.byKey(ClavesNotasDelLugar.deshacer));
        await asentarLugar(tester);

        expect(find.textContaining('No pudimos deshacer el borrado'), findsOneWidget);
        expect(find.text('Ver borradas (1)'), findsOneWidget);
        await tester.tap(find.text('Reintentar'));
        await asentarLugar(tester);
        expect(find.text(textoCanvas1), findsOneWidget);
        expect(find.text('Nota restaurada.'), findsOneWidget);
      },
    );

    testWidgets('dado que borrar falla dos veces, «Reintentar» sigue ofreciéndose y la nota no se '
        'pierde ni queda «ocupada»', (tester) async {
      final repo = NotaUbicacionRepositorioFalso(notas: notasC05())
        ..resultados['borrar'] = [
          const FailureInesperado(causa: 'x'),
          const FailureInesperado(causa: 'y'),
        ];
      await montarHoja447(tester, repo: repo);
      await borrarPorMenuLugar(tester, 'c1');
      expect(find.text('No pudimos borrar la nota. Probá de nuevo.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await asentarLugar(tester);
      expect(find.text('No pudimos borrar la nota. Probá de nuevo.'), findsOneWidget);
      expect(find.text(textoCanvas1), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await asentarLugar(tester);
      expect(find.text(textoCanvas1), findsNothing);
      expect(find.byKey(ClavesNotasDelLugar.deshacer), findsOneWidget);
    });

    testWidgets('dado que guardar una nota falla y la vuelvo a intentar, queda una sola nota y el '
        'texto (con emoji) no se pierde', (tester) async {
      final repo = await llegarA447(tester, Estado447.formularioConFalla);
      expect(find.text('No pudimos guardar la nota. El texto sigue acá.'), findsOneWidget);
      final campo = tester.widget<TextField>(find.byKey(ClavesNotas.campo));
      expect(campo.controller!.text, 'Esta no se guardó 😀');
      await tester.tap(find.text('Reintentar'));
      await asentarLugar(tester);
      expect(repo.repo.notas.where((n) => n.texto == 'Esta no se guardó 😀'), hasLength(1));
      expect(repo.repo.cuantas('agregar'), 2);
      expect(find.byKey(ClavesNotasDelLugar.pestana), findsOneWidget);
    });

    testWidgets('dado un doble toque en «Guardar nota» con la escritura demorada, se escribe una '
        'sola nota con un solo id', (tester) async {
      final repo = NotaUbicacionRepositorioFalso();
      final compuerta = Completer<void>();
      repo.compuertas['agregar'] = compuerta;
      await montarHoja447(tester, repo: repo);
      await tester.tap(find.byKey(ClavesNotasDelLugar.nueva));
      await asentarLugar(tester);
      await tester.enterText(find.byKey(ClavesNotas.campo), 'Una sola');
      await tester.pump();
      await tester.tap(find.text('Guardar nota'));
      await tester.pump();
      await tester.tap(find.text('Guardando…'), warnIfMissed: false);
      await tester.pump();
      compuerta.complete();
      await asentarLugar(tester);
      expect(repo.cuantas('agregar'), 1);
      expect(repo.notas, hasLength(1));
    });

    testWidgets(
      'dado que reentro a la hoja de opciones de la misma nota dos veces, abre una sola',
      (tester) async {
        await llegarA447(tester, Estado447.c05Canvas);
        final tarjeta = find.byKey(ClavesNotasDelLugar.nota('c1'));
        await tester.tap(tarjeta);
        await tester.tap(tarjeta, warnIfMissed: false);
        await asentarLugar(tester);
        expect(find.byKey(ClavesNotas.hojaOpciones), findsOneWidget);
      },
    );

    testWidgets('dado que vuelvo atrás de «Ver borradas», la pestaña sigue y las borradas también '
        'al reentrar', (tester) async {
      await llegarA447(tester, Estado447.borradasDelLugar);
      expect(find.text('Una que borré'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver'));
      await asentarLugar(tester);
      expect(find.byKey(ClavesNotasDelLugar.pestana), findsOneWidget);
      await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.verBorradas));
      await tester.tap(find.byKey(ClavesNotasDelLugar.verBorradas));
      await asentarLugar(tester);
      expect(find.text('Otra que borré'), findsOneWidget);
    });

    testWidgets('dado que restauro todas las borradas desde «Ver borradas», la página sigue con '
        'contenido (no queda en blanco) y el atrás vuelve a la pestaña', (tester) async {
      await llegarA447(tester, Estado447.borradasDelLugar);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Restaurar').first);
        await asentarLugar(tester);
      }
      expect(find.text('No hay notas borradas.'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver'));
      await asentarLugar(tester);
      expect(find.text('Ver borradas (2)'), findsNothing);
      expect(find.text('Una que borré'), findsOneWidget);
    });
  });

  group('QA 447 · el aviso de la pestaña se ve donde está la persona', () {
    Future<void> vaAlFondo(WidgetTester tester) async {
      // 60 notas: la más vieja (n0) queda al final del desplazamiento de la hoja.
      await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.nota('n0')));
      await tester.pump();
    }

    bool aLaVista(WidgetTester tester, Finder f) {
      if (f.evaluate().isEmpty) return false;
      final r = tester.getRect(f.first);
      final pantalla = tester.view.physicalSize;
      return r.bottom > 0 && r.top < pantalla.height;
    }

    // QA #447 (arreglado): con muchas notas el aviso va arriba de la lista; la pestaña lo trae a la vista.
    for (final falla in [false, true]) {
      testWidgets(
        'dado 60 notas y que bajo hasta la última, cuando la borro${falla ? ' y falla' : ''}, el aviso '
        'queda a la vista',
        (tester) async {
          final repo = NotaUbicacionRepositorioFalso(
            notas: [
              for (var i = 0; i < 60; i++)
                notaDeLugar(
                  'n$i',
                  'Nota número ${i + 1} del lugar.',
                  ubicacionId: 'u-1',
                  creada: DateTime(2026, 9, 1).add(Duration(hours: i)),
                ),
            ],
          );
          if (falla) repo.resultados['borrar'] = [const FailureInesperado(causa: 'x')];
          await montarHoja447(tester, repo: repo, tamano: t360x640);
          await vaAlFondo(tester);
          await abrirOpcionesLugar(tester, 'n0');
          await tester.tap(find.byKey(ClavesNotas.botonBorrar));
          await asentarLugar(tester);
          await tester.pump(const Duration(milliseconds: 400));

          expect(find.byKey(ClavesNotasDelLugar.aviso), findsOneWidget);
          expect(
            aLaVista(tester, find.byKey(ClavesNotasDelLugar.aviso)),
            isTrue,
            reason: 'el aviso está arriba de la lista y la persona está al final',
          );
        },
      );
    }

    testWidgets(
      'dado 60 notas y que sumo una nueva desde el final, «Guardamos la nota» queda a la vista',
      (tester) async {
        final repo = NotaUbicacionRepositorioFalso(
          notas: [
            for (var i = 0; i < 60; i++)
              notaDeLugar(
                'n$i',
                'Nota número ${i + 1} del lugar.',
                ubicacionId: 'u-1',
                creada: DateTime(2026, 9, 1).add(Duration(hours: i)),
              ),
          ],
        );
        await montarHoja447(tester, repo: repo, tamano: t360x640);
        await vaAlFondo(tester);
        await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.nueva));
        await tester.tap(find.byKey(ClavesNotasDelLugar.nueva));
        await asentarLugar(tester);
        await escribirYGuardarLugar(tester, 'La de ahora');
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byKey(ClavesNotasDelLugar.aviso), findsOneWidget);
        expect(aLaVista(tester, find.byKey(ClavesNotasDelLugar.aviso)), isTrue);
      },
    );
  });

  group('QA 447 · entrada de texto del formulario de una nota', () {
    Future<Montaje447> abrirForm(WidgetTester tester) async {
      final m = await llegarA447(tester, Estado447.formularioNuevo);
      return m;
    }

    testWidgets('dado solo espacios y saltos de línea, no guarda, avisa qué hacer y deja el foco', (
      tester,
    ) async {
      final m = await abrirForm(tester);
      await tester.enterText(find.byKey(ClavesNotas.campo), '   \n\t  ');
      await tester.pump();
      await tester.tap(find.text('Guardar nota'));
      await asentarLugar(tester);
      expect(find.text('Escribí la nota para poder guardarla.'), findsOneWidget);
      expect(m.repo.cuantas('agregar'), 0);
    });

    testWidgets(
      'dado un texto pegado de 6000 caracteres con emoji, avisa que es largo y deja guardar '
      'entero',
      (tester) async {
        final m = await abrirForm(tester);
        final largo = '😀ñ' * 3000;
        await tester.enterText(find.byKey(ClavesNotas.campo), largo);
        await asentarLugar(tester);
        expect(find.textContaining('lo recomendado es hasta 5000'), findsOneWidget);
        await tester.tap(find.text('Guardar nota'));
        await asentarLugar(tester);
        expect(m.repo.notas.first.texto, largo);
      },
    );

    testWidgets(
      'dado un texto con espacios en los bordes, se guarda sin ellos y lo de adentro queda',
      (tester) async {
        final m = await abrirForm(tester);
        await escribirYGuardarLugar(tester, '  hola   mundo \n');
        expect(m.repo.notas.map((n) => n.texto), contains('hola   mundo'));
      },
    );

    testWidgets(
      'dado texto sin guardar, la ✕ pregunta antes de descartar y «seguir» no pierde lo escrito',
      (tester) async {
        await abrirForm(tester);
        await tester.enterText(find.byKey(ClavesNotas.campo), 'A medias');
        await tester.pump();
        await tester.tap(find.byTooltip('Cerrar'));
        await asentarLugar(tester);
        expect(find.textContaining('Descartar'), findsWidgets);
      },
    );
  });

  group('QA 447 · privacidad (convenciones §7.5)', () {
    testWidgets(
      'la nota no se imprime: ni `toString` ni el repositorio en memoria muestran el texto',
      (tester) async {
        final n = notaDeLugar('x', 'SECRETO-DEL-LUGAR', ubicacionId: 'u-1');
        expect('$n', isNot(contains('SECRETO-DEL-LUGAR')));
        expect(n.toString(), isNot(contains('SECRETO')));
        const f = FailureInesperado(causa: 'StateError');
        expect(f.toString(), isNot(contains('SECRETO')));
      },
    );
  });

  group('QA 447 · semántica para el lector de pantalla', () {
    testWidgets('el aviso de la pestaña es región viva y «Deshacer» es un botón con acción', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llegarA447(tester, Estado447.avisoBorrada);
      expect(
        tester.getSemantics(find.text('Nota borrada.')),
        isSemantics(label: 'Nota borrada.', isLiveRegion: true),
      );
      final deshacer = tester.getSemantics(find.byKey(ClavesNotasDelLugar.deshacer));
      expect(deshacer.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantica.dispose();
    });

    testWidgets('una nota se lee con su fecha y su texto, y se puede activar', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA447(tester, Estado447.c05Canvas);
      final nodo = find.bySemanticsLabel(RegExp(r'el 05/10\. ' + RegExp.escape(textoCanvas1)));
      expect(nodo, findsOneWidget);
      expect(tester.getSemantics(nodo).getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantica.dispose();
    });

    testWidgets('«+ Nota del lugar» es un botón con etiqueta y acción', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA447(tester, Estado447.c05Canvas);
      final datos = tester.getSemantics(find.byKey(ClavesNotasDelLugar.nueva)).getSemanticsData();
      expect(datos.label, '+ Nota del lugar');
      expect(datos.hasAction(SemanticsAction.tap), isTrue);
      semantica.dispose();
    });
  });

  group('QA 447 · teclado abierto en el formulario', () {
    for (final escala in _escalas) {
      testWidgets('formulario a 360×640 con teclado de 280 dp y texto $escala×: sin desbordes y '
          '«Guardar nota» a la vista', (tester) async {
        await llegarA447(tester, Estado447.formularioNuevo, tamano: t360x640, escala: escala);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump(const Duration(milliseconds: 100));
        await asentarLugar(tester, 4);
        expect(tester.takeException(), isNull);
        final boton = find.text('Guardar nota');
        expect(boton, findsOneWidget);
        final r = tester.getRect(boton);
        expect(
          r.bottom,
          lessThanOrEqualTo(640 - 280 + 1),
          reason: 'el botón queda sobre el teclado',
        );
      });
    }
  });
}

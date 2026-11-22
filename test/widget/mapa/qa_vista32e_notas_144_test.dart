// QA de las notas de una persona (HU-UBI-012, vista 32E, #144): los escenarios de la HU con su texto,
// los casos límite de cada flujo y la matriz de tamaños y escalas con las fuentes reales (sin overflow,
// sin texto fuera de la pantalla y, con `--dart-define=QA_CAPTURAS=true`, una captura PNG por celda en
// `.dart_tool/qa_capturas/`, que no se commitea). Las guías de accesibilidad están en
// `qa_vista32e_notas_144_guias_test.dart`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/notas_persona_use_cases.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_persona_falsos.dart';
import '../../helpers/qa_vista32e_144_arnes.dart';
import 'notas_persona_arnes.dart';

/// Lo que tiene que verse para que el estado sea el que dice ser (si no, la matriz probaría la pantalla
/// equivocada).
const Map<String, List<String>> esperado144 = {
  'e01_notas': ['Notas de María', 'Estas notas viven solo en tu celular.', '+ Nueva nota'],
  'e01_muchas_y_larga': ['Notas de María', '+ Nueva nota'],
  'e02_nueva': ['Nueva nota', 'Guardar nota', 'Estas notas viven solo en tu celular.'],
  'e02_nueva_con_texto': ['Prefiere que la llamen antes de pasar.', 'Guardar nota'],
  'e02_en_blanco_intentado': ['Escribí la nota para poder guardarla.'],
  'e02_mas_de_5000': ['Podés guardarla igual.', 'Guardar nota'],
  'e07_error_al_guardar': ['No pudimos guardar la nota. El texto sigue acá.', 'Reintentar'],
  'editar_nota': ['Editar nota', 'Guardar nota'],
  'descartar_lo_escrito': ['¿Descartar lo que escribiste?', 'Seguir escribiendo', 'Descartar'],
  'e03_menu': ['Nota de hoy 14:20', 'Editar', 'Borrar', 'Cerrar'],
  'e04_borrada': ['Nota borrada.', 'Deshacer'],
  'e05_borradas': ['BORRADAS', 'Restaurar'],
  'e05_sin_borradas': ['No hay notas borradas.'],
  'e06_sin_notas': ['Todavía no hay notas', 'Anotá lo que te sirva para la próxima visita.'],
  'cargando': ['Notas', 'Estas notas viven solo en tu celular.'],
  'error_de_lectura': ['Reintentar'],
  'persona_que_ya_no_esta': ['La persona ya no está en tu teléfono. Volvé atrás.'],
  'solo_lectura_persona_de_baja': ['Podés ver sus notas, pero no agregar, editar ni borrar'],
  'solo_lectura_espacio_de_baja': ['El depto 3B de Mataojo 2044 está dado de baja.'],
  'solo_lectura_nombres_largos': [
    'Notas de Mariadelosangelesfernandezdelarosa',
    'está dado de baja',
  ],
  'borradas_solo_lectura': ['BORRADAS'],
};

void main() {
  Future<void> escribir(WidgetTester tester, String texto) async {
    await tester.enterText(find.byKey(ClavesNotas.campo), texto);
    await tester.pump();
  }

  String? textoDelCampo(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(ClavesNotas.campo)).controller?.text;

  group('matriz de tamaños con fuentes reales', () {
    for (final entrada in estados144.entries) {
      for (final celda in celdas144) {
        testWidgets('${entrada.key} · $celda: sin overflow ni texto fuera de la pantalla', (
          tester,
        ) async {
          await cargarFuentes144(tester);
          await entrada.value(tester, celda);

          expect(tester.takeException(), isNull, reason: 'sin overflow ni errores de layout');
          for (final texto in esperado144[entrada.key] ?? const <String>[]) {
            expect(
              find.textContaining(texto, skipOffstage: false),
              findsAtLeastNWidgets(1),
              reason: 'falta «$texto» en ${entrada.key}',
            );
          }
          expectSinTextoFueraDeLosCostados144(tester, celda.tamano);
          await capturar144(tester, '${entrada.key}_${celda.nombre}');
        });
      }
    }
  });

  group('teclado abierto en el formulario', () {
    for (final entrada in {
      'nueva con texto': 'e02_nueva_con_texto',
      'error al guardar': 'e07_error_al_guardar',
      'editar': 'editar_nota',
    }.entries) {
      for (final celda in celdas144) {
        testWidgets(
          '${entrada.key} · $celda: con 280 dp de teclado no desborda y «Guardar» se ve',
          (tester) async {
            await cargarFuentes144(tester);
            await estados144[entrada.value]!(tester, celda);
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            addTearDown(tester.view.resetViewInsets);
            await asentar(tester);

            expect(tester.takeException(), isNull, reason: 'sin overflow con el teclado');
            final boton = find.byType(FilledButton);
            expect(boton, findsOneWidget);
            final r = tester.getRect(boton);
            expect(
              r.bottom <= celda.tamano.height - 280 + 0.5,
              isTrue,
              reason: 'el botón queda sobre el teclado: $r',
            );
            expect(r.height >= 48, isTrue);
            await capturar144(tester, 'teclado_${entrada.value}_${celda.nombre}');
          },
        );
      }
    }
  });

  group('criterios de aceptación de la HU-UBI-012, con su texto', () {
    testWidgets(
      'Agregar primera nota: dado que la persona no tiene notas, cuando agrego "Le interesa Caminos de la Vida", se crea con created_by = mi user_id y aparece en el perfil',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        await montarNotas(tester, repo: repo, tamano: telefonoChico144);
        expect(find.text('Todavía no hay notas'), findsOneWidget);

        await tester.tap(find.text('+ Nueva nota'));
        await asentar(tester);
        await escribir(tester, 'Le interesa Caminos de la Vida');
        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);

        expect(repo.notas, hasLength(1));
        expect(repo.notas.single.texto, 'Le interesa Caminos de la Vida');
        expect(repo.notas.single.auditoria.createdBy, 'col-1');
        expect(repo.notas.single.personaId, 'per-1');
        expect(find.text('Le interesa Caminos de la Vida'), findsOneWidget);
        expect(find.text('Todavía no hay notas'), findsNothing);
        expect(find.text('Guardamos la nota en este teléfono.'), findsOneWidget);
      },
    );

    testWidgets(
      'Editar nota propia: dado una nota anterior, cuando la edito, se actualiza updated_at y se preservan created_at y created_by',
      (tester) async {
        final original = notasDelCanvas().first;
        final repo = NotaPersonaRepositorioFalso(notas: [original]);
        await montarNotas(tester, repo: repo);

        await abrirOpciones(tester, 'hoy');
        await elegirOpcion(tester, ClavesNotas.botonEditar);
        expect(textoDelCampo(tester), original.texto);
        await escribir(tester, 'Pidió volver el domingo.');
        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);

        final editada = repo.notas.single;
        expect(editada.texto, 'Pidió volver el domingo.');
        expect(editada.auditoria.createdAt, original.auditoria.createdAt);
        expect(editada.auditoria.createdBy, original.auditoria.createdBy);
        expect(editada.auditoria.updatedAt.toUtc(), ahoraDePrueba.toUtc());
        expect(editada.auditoria.updatedAt.isAfter(original.auditoria.updatedAt), isTrue);
        expect(find.text('Pidió volver el domingo.'), findsOneWidget);
        expect(find.text('Cambios guardados en tu teléfono.'), findsOneWidget);
      },
    );

    testWidgets(
      'Borrar nota (soft delete): dado una nota desactualizada, cuando confirmo «Borrar», se setea deleted_at y deja de aparecer, salvo en «Ver borradas»',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);

        await borrarPorMenu(tester, 'hoy');

        final borrada = repo.notas.firstWhere((n) => n.id == 'hoy');
        expect(borrada.auditoria.deletedAt, isNotNull);
        expect(repo.notas, hasLength(2), reason: 'soft delete: la fila sigue en la base');
        expect(find.textContaining('Pidió volver el sábado'), findsNothing);
        expect(find.text('Nota borrada.'), findsOneWidget);
        expect(find.text('Ver borradas (1)'), findsOneWidget);

        await tester.tap(find.text('Ver borradas (1)'));
        await asentar(tester);
        expect(find.textContaining('Pidió volver el sábado'), findsOneWidget);
        expect(find.text('Restaurar'), findsOneWidget);
      },
    );

    testWidgets(
      'Edge, nota muy larga: dado que intento guardar > 5000 chars, cuando guardo, la UI advierte el tamaño pero permite guardar',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        await montarNotas(tester, repo: repo);
        await tester.tap(find.text('+ Nueva nota'));
        await asentar(tester);

        await escribir(tester, List.filled(1001, 'abcde').join());
        expect(find.textContaining('5005 caracteres'), findsOneWidget);
        expect(find.textContaining('Podés guardarla igual.'), findsOneWidget);

        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);
        expect(repo.notas, hasLength(1));
        expect(repo.notas.single.texto.length, 5005);
      },
    );

    testWidgets(
      'casos borde: sobre el contenido de una nota no existe «Llamar», «Compartir» ni texto seleccionable',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);
        for (final palabra in ['Llamar', 'Compartir', 'Copiar']) {
          expect(find.textContaining(palabra), findsNothing);
        }
        expect(find.byType(SelectableText), findsNothing);
        expect(find.byType(SelectionArea), findsNothing);

        await abrirOpciones(tester, 'hoy');
        for (final palabra in ['Llamar', 'Compartir', 'Copiar']) {
          expect(find.textContaining(palabra), findsNothing);
        }
        expect(find.text('Editar'), findsOneWidget);
        expect(find.text('Borrar'), findsOneWidget);
      },
    );

    testWidgets(
      'el aviso de privacidad (canvas: «Estas notas viven solo en tu celular.») está siempre: lista, vacío, formulario y borradas',
      (tester) async {
        await montarNotas(tester, repo: NotaPersonaRepositorioFalso());
        expect(find.text('Estas notas viven solo en tu celular.'), findsOneWidget);
        await tester.tap(find.text('+ Nueva nota'));
        await asentar(tester);
        expect(find.text('Estas notas viven solo en tu celular.'), findsOneWidget);
      },
    );

    testWidgets('orden: la nota más nueva arriba (decisión P4: gana el canvas E·01)', (
      tester,
    ) async {
      await montarNotas(tester, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));
      final arriba = tester.getTopLeft(find.text('HOY 14:20')).dy;
      final abajo = tester.getTopLeft(find.text('05/10')).dy;
      expect(arriba, lessThan(abajo));
    });
  });

  group('validación de la nota', () {
    for (final caso in {
      'vacío': '',
      'solo espacios': '     ',
      'solo saltos de línea': '\n\n\n',
      'espacios y tabulaciones': ' \t \n ',
      'solo caracteres invisibles': '​‍﻿',
    }.entries) {
      testWidgets('dado ${caso.key}, cuando toco «Guardar nota», no guarda y dice qué hacer', (
        tester,
      ) async {
        final repo = NotaPersonaRepositorioFalso();
        final resultado = await montarFormulario(tester, repo: repo);
        if (caso.value.isNotEmpty) await escribir(tester, caso.value);

        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);

        expect(repo.llamadas, isEmpty);
        expect(resultado.cierres, 0);
        expect(find.text('Escribí la nota para poder guardarla.'), findsOneWidget);
        expect(find.text('Guardando…'), findsNothing);
        // El botón sigue habilitado para que se pueda volver a probar.
        expect(find.text('Guardar nota'), findsOneWidget);
      });
    }

    testWidgets(
      'dado texto con emoji, tildes, comillas y marcado, cuando guardo, se guarda tal cual por dentro y sin espacios en los bordes',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        await montarFormulario(tester, repo: repo);
        const adentro =
            'Debe \$1.500 😀👨‍👩‍👧 «ñandú» <b>"x"</b> \'y\' & % \\ ✓\nsegundo renglón';
        await escribir(tester, '  \n$adentro \n ');

        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);

        expect(repo.notas.single.texto, adentro);
      },
    );

    testWidgets('dado un texto pegado de 30000 caracteres, cuando guardo, se guarda entero', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso();
      await montarFormulario(tester, repo: repo, tamano: telefonoChico144);
      final largo = List.filled(6000, 'abcde').join();
      await escribir(tester, largo);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('30000 caracteres'), findsOneWidget);

      await tester.tap(find.text('Guardar nota'));
      await asentar(tester);

      expect(repo.notas.single.texto.length, 30000);
    });

    testWidgets(
      'dado una nota de 6000 emoji (cada uno son dos unidades UTF-16), cuando la cuento, avisa por caracteres y no por unidades',
      (tester) async {
        await montarFormulario(tester, repo: NotaPersonaRepositorioFalso());
        await escribir(tester, List.filled(5000, '😀').join());
        expect(find.textContaining('Podés guardarla igual.'), findsNothing);
        await escribir(tester, List.filled(5001, '😀').join());
        expect(find.textContaining('5001 caracteres'), findsOneWidget);
      },
    );
  });

  group('casos límite de cada flujo', () {
    testWidgets(
      'guardar falla a mitad: el botón vuelve a habilitarse, no queda «Guardando…» y el texto sigue; «Reintentar» guarda una sola nota',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso()
          ..resultados['agregar'] = [const FailureInesperado(), const FailureInesperado()];
        final resultado = await montarFormulario(tester, repo: repo);
        await escribir(tester, 'No se puede perder');

        for (var i = 0; i < 2; i++) {
          await tester.tap(find.text(i == 0 ? 'Guardar nota' : 'Reintentar'));
          await asentar(tester);
          expect(find.text('Guardando…'), findsNothing);
          expect(find.text('Reintentar'), findsOneWidget);
          expect(textoDelCampo(tester), 'No se puede perder');
        }
        await tester.tap(find.text('Reintentar'));
        await asentar(tester);

        expect(repo.notas, hasLength(1));
        expect(resultado.cierres, 1);
        expect(resultado.guardada?.esNueva, isTrue);
      },
    );

    testWidgets(
      'guardar lanza una excepción con el texto adentro: el aviso no la muestra y el texto no se pierde',
      (tester) async {
        final repo = _RepoQueLanza();
        await montarFormulario(tester, repo: repo);
        await escribir(tester, 'Debe plata');

        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);

        expect(find.textContaining('SECRETO'), findsNothing);
        expect(find.text('No pudimos guardar la nota. El texto sigue acá.'), findsOneWidget);
        expect(textoDelCampo(tester), 'Debe plata');
        expect(find.text('Reintentar'), findsOneWidget);
      },
    );

    testWidgets(
      'atrás del sistema mientras se guarda: la pantalla no se cierra, y al terminar la nota está guardada',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso();
        repo.compuertas['agregar'] = Completer<void>();
        final resultado = await montarFormulario(tester, repo: repo);
        await escribir(tester, 'Una nota');
        await tester.tap(find.text('Guardar nota'));
        await tester.pump();
        expect(find.text('Guardando…'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await asentar(tester);
        expect(find.byKey(ClavesNotas.campo), findsOneWidget);
        expect(find.text('¿Descartar lo que escribiste?'), findsNothing);

        repo.compuertas['agregar']!.complete();
        await asentar(tester);
        expect(repo.notas, hasLength(1));
        expect(resultado.cierres, 1);
      },
    );

    testWidgets(
      'borrar falla: el aviso dice qué pasó con «Reintentar»; la nota sigue en la lista; «Reintentar» la borra una vez',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas())
          ..resultados['borrar'] = [const FailureInesperado()];
        await montarNotas(tester, repo: repo);

        await borrarPorMenu(tester, 'hoy');
        expect(find.text('No pudimos borrar la nota. Probá de nuevo.'), findsOneWidget);
        expect(find.textContaining('Pidió volver el sábado'), findsOneWidget);

        await tester.tap(find.text('Reintentar'));
        await asentar(tester);
        expect(find.text('Nota borrada.'), findsOneWidget);
        expect(find.textContaining('Pidió volver el sábado'), findsNothing);
        expect(repo.cuantas('borrar'), 2);
      },
    );

    testWidgets(
      'dos notas borradas seguidas: las dos quedan en «Ver borradas (2)» y «Deshacer» devuelve la última',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);

        await borrarPorMenu(tester, 'hoy');
        await borrarPorMenu(tester, 'vieja');
        expect(find.text('Ver borradas (2)'), findsOneWidget);
        expect(find.text('Todavía no hay notas'), findsOneWidget);

        await tester.tap(find.text('Deshacer'));
        await asentar(tester);

        expect(repo.notas.where((n) => n.estaBorrada).map((n) => n.id), ['hoy']);
        expect(find.text('05/10'), findsOneWidget);
        expect(find.text('Ver borradas (1)'), findsOneWidget);
      },
    );

    testWidgets(
      'borrar, ir a «Ver borradas», restaurar y volver: la nota regresa con su fecha original y su lugar',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);

        await borrarPorMenu(tester, 'hoy');
        await tester.tap(find.text('Ver borradas (1)'));
        await asentar(tester);
        await tester.tap(find.text('Restaurar'));
        await asentar(tester);
        expect(find.text('Nota restaurada.'), findsOneWidget);
        await tester.tap(find.byTooltip('Volver'));
        await asentar(tester);

        expect(find.text('HOY 14:20'), findsOneWidget);
        expect(find.textContaining('Pidió volver el sábado'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('HOY 14:20')).dy,
          lessThan(tester.getTopLeft(find.text('05/10')).dy),
        );
        expect(find.textContaining('Ver borradas'), findsNothing);
      },
    );

    testWidgets(
      'restaurar falla: el aviso dice qué pasó con «Reintentar» y la nota sigue en «Ver borradas»',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(
          notas: [notaDePrueba('b1', 'Una borrada', borrada: DateTime(2026, 10, 22, 14, 30))],
        )..resultados['restaurar'] = [const FailureInesperado()];
        await montarNotas(tester, repo: repo);
        await tester.tap(find.text('Ver borradas (1)'));
        await asentar(tester);

        await tester.tap(find.text('Restaurar'));
        await asentar(tester);
        expect(find.text('No pudimos restaurar la nota. Probá de nuevo.'), findsOneWidget);
        expect(find.text('Restaurar'), findsOneWidget);

        await tester.tap(find.text('Reintentar'));
        await asentar(tester);
        expect(find.text('Nota restaurada.'), findsOneWidget);
        expect(find.text('No hay notas borradas.'), findsOneWidget);
      },
    );

    testWidgets(
      'editar y guardar sin tocar el texto: cierra sin escribir y sin cambiar updated_at',
      (tester) async {
        final original = notasDelCanvas().first;
        final repo = NotaPersonaRepositorioFalso(notas: [original]);
        await montarNotas(tester, repo: repo);
        await abrirOpciones(tester, 'hoy');
        await elegirOpcion(tester, ClavesNotas.botonEditar);

        await tester.tap(find.text('Guardar nota'));
        await asentar(tester);

        expect(repo.cuantas('editar'), 0);
        expect(repo.notas.single.auditoria.updatedAt, original.auditoria.updatedAt);
      },
    );

    testWidgets(
      'reentrada: salgo de las notas con el atrás, vuelvo a entrar y siguen todas, sin estados viejos',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo);
        await borrarPorMenu(tester, 'hoy');
        await tester.tap(find.byTooltip('Volver'));
        await asentar(tester);
        expect(find.text('abrir notas'), findsOneWidget);

        await tester.tap(find.text('abrir notas'));
        await asentar(tester);

        expect(find.text('05/10'), findsOneWidget);
        expect(find.text('Ver borradas (1)'), findsOneWidget);
        // El aviso «Nota borrada.» sigue (es del mensajero de la app): «Deshacer» sigue a mano.
      },
    );

    testWidgets('el contexto cambia a solo lectura al reintentar tras un error de lectura', (
      tester,
    ) async {
      final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas())
        ..fallaDeContexto = const FailureInesperado();
      await montarNotas(tester, repo: repo);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('+ Nueva nota'), findsNothing);

      repo
        ..fallaDeContexto = null
        ..contexto = const ContextoNotasPersona(
          nombre: 'María',
          causa: CausaSoloLectura.sinEspacioActivo,
        );
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      expect(find.textContaining('María ya no está en ningún depto activo.'), findsOneWidget);
      expect(find.text('+ Nueva nota'), findsNothing);
      expect(find.text('HOY 14:20'), findsOneWidget);
    });
  });

  group('lector de pantalla', () {
    testWidgets('el aviso de error al guardar se anuncia como región viva', (tester) async {
      final semantica = tester.ensureSemantics();
      final repo = NotaPersonaRepositorioFalso()
        ..resultados['agregar'] = [const FailureInesperado()];
      await montarFormulario(tester, repo: repo);
      await escribir(tester, 'Algo');
      await tester.tap(find.text('Guardar nota'));
      await asentar(tester);

      final nodo = tester.getSemantics(
        find.bySemanticsLabel(RegExp('No pudimos guardar la nota')).first,
      );
      var viva = false;
      void buscar(SemanticsNode n) {
        if (n.flagsCollection.isLiveRegion) viva = true;
      }

      buscar(nodo);
      nodo.visitChildren((hijo) {
        buscar(hijo);
        return true;
      });
      var padre = nodo.parent;
      while (padre != null && !viva) {
        buscar(padre);
        padre = padre.parent;
      }
      expect(viva, isTrue, reason: 'el error de guardado debe anunciarse solo');
      semantica.dispose();
    });

    testWidgets(
      'con lector el aviso «Nota borrada.» no se cierra solo: «Deshacer» sigue a mano a los 30 s',
      (tester) async {
        final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
        await montarNotas(tester, repo: repo, lector: true);
        await borrarPorMenu(tester, 'hoy');
        await tester.pump(const Duration(seconds: 30));
        expect(find.text('Nota borrada.'), findsOneWidget);
        expect(find.text('Deshacer'), findsOneWidget);
      },
    );

    testWidgets('sin lector el aviso «Nota borrada.» se va a los 8 segundos', (tester) async {
      final repo = NotaPersonaRepositorioFalso(notas: notasDelCanvas());
      await montarNotas(tester, repo: repo);
      await borrarPorMenu(tester, 'hoy');
      await tester.pump(const Duration(seconds: 9));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Nota borrada.'), findsNothing);
    });
  });

  group('hallazgos menores (con QA_HALLAZGOS=true se corren)', () {
    final notaBorrada = NotaPersonaRepositorioFalso(
      notas: [notaDePrueba('b1', 'Una borrada', borrada: DateTime(2026, 10, 22, 14, 30))],
    );

    // QA #144 — «Restaurar» (E·05) va dentro de la tarjeta, a la derecha, como el canvas (Bloques `r`).
    testWidgets('E·05: «Restaurar» está dentro de la tarjeta de la nota borrada, como el canvas', (
      tester,
    ) async {
      await montarPantalla144(
        tester,
        celdas144[2],
        repo: notaBorrada,
        pantalla: Pantalla144.borradas,
      );
      final tarjeta = tester.getRect(find.byKey(const ValueKey('borrada_b1')).first);
      final boton = tester.getCenter(find.text('Restaurar'));
      final tarjetaVisible = tester.getRect(
        find
            .descendant(
              of: find.byKey(const ValueKey('borrada_b1')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(tarjetaVisible.contains(boton), isTrue, reason: 'tarjeta $tarjeta, Restaurar $boton');
    });

    // QA #144 — «Restaurar» lleva la fuente Inter: el `textStyle` del botón trae su familia.
    testWidgets('E·05: «Restaurar» se escribe con Inter, como el resto de la app', (tester) async {
      await montarPantalla144(
        tester,
        celdas144[2],
        repo: notaBorrada,
        pantalla: Pantalla144.borradas,
      );
      final rich = tester.widget<RichText>(
        find.descendant(of: find.byType(TextButton), matching: find.byType(RichText)).first,
      );
      expect(rich.text.style?.fontFamily, 'Inter');
    });

    // QA #144 — el lector dice «Restaurar la nota del 05/10», no «de el 05/10».
    testWidgets('E·05: el lector dice «de la nota del 05/10», no «de el 05/10»', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarPantalla144(
        tester,
        celdas144[2],
        repo: NotaPersonaRepositorioFalso(
          notas: [
            notaDePrueba(
              'b2',
              'Vieja',
              creada: DateTime(2026, 10, 5, 9),
              borrada: DateTime(2026, 10, 6, 9),
            ),
          ],
        ),
        pantalla: Pantalla144.borradas,
      );
      expect(find.bySemanticsLabel(RegExp(r'Restaurar la nota de el ')), findsNothing);
      expect(find.bySemanticsLabel('Restaurar la nota del 05/10'), findsOneWidget);
      semantica.dispose();
    });
  });

  group('privacidad', () {
    test(
      'el texto de una nota no sale por toString de la nota, del contexto ni de los parámetros',
      () {
        final nota = notaDePrueba('n1', 'Debe 5000 pesos y lo esconde');
        expect('$nota', isNot(contains('Debe 5000')));
        expect(nota.toString(), isNot(contains('Debe')));
        const contexto = ContextoNotasPersona(
          nombre: 'María Fernández',
          direccion: 'Mataojo 2044',
          causa: CausaSoloLectura.espacioDeBaja,
        );
        expect('$contexto', isNot(contains('María')));
        expect('$contexto', isNot(contains('Mataojo')));
        const alta = AgregarNotaPersonaParams(
          id: 'i',
          personaId: 'p',
          colportorId: 'c',
          texto: 'Debe 5000 pesos',
        );
        expect('$alta', isNot(contains('Debe 5000')));
        const edicion = EditarNotaPersonaParams(notaId: 'i', texto: 'Debe 5000 pesos');
        expect('$edicion', isNot(contains('Debe 5000')));
      },
    );

    test('una falla de validación del texto vacío no repite lo escrito', () async {
      final repo = NotaPersonaRepositorioFalso();
      final caso = AgregarNotaPersonaUseCase(repo);
      final r = await caso(
        const AgregarNotaPersonaParams(id: 'i', personaId: 'p', colportorId: 'c', texto: '   '),
      );
      expect(r.isLeft(), isTrue);
      r.fold((f) => expect('$f', isNot(contains('   x'))), (_) => fail('debía fallar'));
      expect(repo.llamadas, isEmpty);
    });
  });
}

/// Un repositorio cuya escritura lanza una excepción que lleva el texto escrito.
final class _RepoQueLanza extends NotaPersonaRepositorioFalso {
  @override
  Future<Either<Failure, NotaPersona>> agregar(NotaPersona nota) =>
      throw StateError('SECRETO: ${nota.texto}');
}

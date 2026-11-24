// HU-UBI-008, vista 39 (#653): anotar el nombre de la persona de forma rápida y OPCIONAL, sin pedirlo
// al crear la casa (decisión de Cristian, 04/11). Tres lugares: R·04 («¿Con quién es la entrevista?»,
// casa sin personas) con «Todavía no sé con quién», la pestaña Personas vacía de una casa nueva con
// «+ Agregar persona» (alta corta, 32 A), y que el alta de la casa no pide nombre. Los casos límite
// de cada flujo: doble toque, falla a mitad, dos acciones seguidas, volver y reentrar, datos límite
// y texto al 200 y 300 %.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/eleccion_de_entrevista.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_de_la_entrevista.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_317_arnes.dart' show EstadoAlta, abrirEn;
import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;
import '../../helpers/persona_falsos.dart';
import 'hoja_con_quien_arnes.dart';
import 'personas_arnes.dart';
import 'registrar_visita_arnes.dart';

const _empezar = 'Empezar entrevista';
const _todaviaNoSe = 'Todavía no sé con quién';
const _nombre = 'Obligatorio';
const _apellido = 'Apellido';

Finder _campo(String sugerencia) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == sugerencia);

Finder get _botonEmpezar => find.widgetWithText(FilledButton, _empezar);
Finder get _botonVolver => find.widgetWithText(OutlinedButton, 'Volver');
Finder get _botonSinNombre => find.byKey(ClavesConQuien.todaviaNoSe);

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

void main() {
  group('R·04 · el nombre es opcional: «Todavía no sé con quién»', () {
    testWidgets(
      'dado una casa sin personas, cuando se abre, ofrece «Todavía no sé con quién» entre '
      '«Empezar entrevista» y «Volver»',
      (tester) async {
        await montarConQuien(tester);

        expect(_botonSinNombre, findsOneWidget);
        expect(find.text(_todaviaNoSe), findsOneWidget);
        final y = [
          _botonEmpezar,
          _botonSinNombre,
          _botonVolver,
        ].map((f) => tester.getTopLeft(f).dy).toList();
        expect(
          y,
          orderedEquals([...y]..sort()),
          reason: 'el orden es Empezar, Todavía no sé, Volver',
        );
        // «Empezar entrevista» sigue pidiendo el nombre: el canvas no cambia.
        expect(find.text('NOMBRE'), findsOneWidget);
        expect(find.text('APELLIDO (OPCIONAL)'), findsOneWidget);
        expect(tester.widget<TextButton>(_botonSinNombre).onPressed, isNotNull);
      },
    );

    testWidgets('entrevista dada sin nombre: «Todavía no sé con quién» sigue sin persona y no '
        'guarda ni inventa a nadie', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarConQuien(tester, repo: repo);

      await _tocar(tester, _botonSinNombre);

      expect(resultado.eleccion, const EntrevistaSinPersona());
      expect(resultado.sinPersona, isTrue);
      expect(resultado.elegida, isNull);
      expect(resultado.cierres, 1);
      expect(repo.recibidas, isEmpty);
      expect(find.text('¿Con quién es la entrevista?'), findsNothing);
      expect(find.text('Escribí al menos el nombre.'), findsNothing, reason: 'no valida nada');
    });

    testWidgets('entrevista dada con nombre: guarda a la persona y devuelve con quién es', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarConQuien(tester, repo: repo);

      await _escribir(tester, _nombre, 'Pedro');
      await _tocar(tester, _botonEmpezar);

      expect(repo.recibidas.single.persona.nombre, 'Pedro');
      expect(resultado.eleccion, isA<EntrevistaConPersona>());
      expect(
        resultado.elegida,
        PersonaDeLaEntrevista(
          personaId: repo.recibidas.single.persona.id,
          espacioPersonaId: repo.recibidas.single.vinculo.id,
        ),
      );
      expect(resultado.sinPersona, isFalse);
    });

    testWidgets('con un nombre escrito a medias, «Todavía no sé con quién» lo deja y no guarda', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarConQuien(tester, repo: repo);
      await _escribir(tester, _nombre, 'Pedro');
      await _escribir(tester, _apellido, 'Gómez');

      await _tocar(tester, _botonSinNombre);

      expect(resultado.sinPersona, isTrue);
      expect(repo.recibidas, isEmpty);
    });

    testWidgets(
      'una sola persona cargada: el paso se salta y sigue con ella, no con «sin persona»',
      (tester) async {
        final repo = PersonaRepositorioFalso()
          ..sembrar([clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez')]);
        final resultado = await montarConQuien(tester, repo: repo);

        expect(resultado.eleccion, isA<EntrevistaConPersona>());
        expect(resultado.elegida?.personaId, 'pedro');
        expect(_botonSinNombre, findsNothing);
      },
    );

    testWidgets('«Volver» sigue cerrando sin elegir nada (no es «sin persona»)', (tester) async {
      final resultado = await montarConQuien(tester);

      await _tocar(tester, _botonVolver);

      expect(resultado.eleccion, isNull);
      expect(resultado.sinPersona, isFalse);
      expect(resultado.cierres, 1);
    });

    testWidgets('el lector de pantalla lo lee como botón con su rótulo', (tester) async {
      final handle = tester.ensureSemantics();
      await montarConQuien(tester);

      final datos = tester.getSemantics(_botonSinNombre).getSemanticsData();

      expect(datos.label, _todaviaNoSe);
      expect(datos.flagsCollection.isButton, isTrue);
      expect(datos.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    group('casos límite', () {
      testWidgets('doble toque en «Todavía no sé con quién»: un solo cierre', (tester) async {
        final repo = PersonaRepositorioFalso();
        final resultado = await montarConQuien(tester, repo: repo);

        // Dos toques seguidos, sin un solo fotograma entre ellos.
        await tester.tap(_botonSinNombre);
        await tester.tap(_botonSinNombre, warnIfMissed: false);
        await asentar(tester);

        expect(resultado.cierres, 1);
        expect(resultado.rutas.cierres, 1);
        expect(resultado.abiertas, 0);
        expect(resultado.sinPersona, isTrue);
        expect(repo.recibidas, isEmpty);
      });

      testWidgets('doble activación por accesibilidad: un solo cierre', (tester) async {
        final handle = tester.ensureSemantics();
        final resultado = await montarConQuien(tester);

        // Las acciones de accesibilidad no pasan por la ruta que ignora el toque mientras se cierra.
        final boton = find.semantics.byLabel(_todaviaNoSe);
        tester.semantics.performAction(boton, SemanticsAction.tap);
        tester.semantics.performAction(boton, SemanticsAction.tap);
        await asentar(tester);

        expect(resultado.cierres, 1);
        expect(resultado.rutas.cierres, 1);
        expect(resultado.sinPersona, isTrue);
        handle.dispose();
      });

      testWidgets('mientras se guarda a la persona queda apagado y no corta el guardado', (
        tester,
      ) async {
        final compuerta = Completer<void>();
        final repo = PersonaRepositorioFalso(compuerta: compuerta);
        final resultado = await montarConQuien(tester, repo: repo);
        await _escribir(tester, _nombre, 'Pedro');

        await tester.tap(_botonEmpezar);
        await tester.pump();
        // Dos acciones seguidas antes de que termine la primera.
        await tester.tap(_botonSinNombre, warnIfMissed: false);
        await tester.pump();

        expect(tester.widget<TextButton>(_botonSinNombre).onPressed, isNull);
        expect(resultado.cierres, 0);

        compuerta.complete();
        await asentar(tester);

        expect(repo.recibidas, hasLength(1));
        expect(resultado.cierres, 1);
        expect(resultado.eleccion, isA<EntrevistaConPersona>(), reason: 'ganó el guardado');
      });

      testWidgets('falla a mitad del guardado: se puede seguir sin nombre y nada queda ocupado', (
        tester,
      ) async {
        final repo = PersonaRepositorioFalso(resultados: [fallaDeGuardado]);
        final resultado = await montarConQuien(tester, repo: repo);
        await _escribir(tester, _nombre, 'Pedro');
        await _tocar(tester, _botonEmpezar);

        expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.widget<TextButton>(_botonSinNombre).onPressed, isNotNull);
        expect(tester.widget<FilledButton>(_botonEmpezar).onPressed, isNotNull);

        await _tocar(tester, _botonSinNombre);

        expect(resultado.sinPersona, isTrue);
        expect(resultado.cierres, 1);
      });

      testWidgets('volver y reentrar: «Todavía no sé con quién» vuelve a estar, sin nada trabado', (
        tester,
      ) async {
        final resultado = await montarConQuien(tester);
        await _tocar(tester, _botonSinNombre);
        expect(resultado.sinPersona, isTrue);

        await abrirPaso(tester);

        expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
        expect(tester.widget<TextButton>(_botonSinNombre).onPressed, isNotNull);

        await _tocar(tester, _botonVolver);

        expect(resultado.eleccion, isNull, reason: 'la segunda vez se volvió sin elegir');
        expect(resultado.cierres, 2);
      });

      testWidgets('el atrás del sistema cierra sin elegir, aunque exista «Todavía no sé»', (
        tester,
      ) async {
        final resultado = await montarConQuien(tester);

        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(resultado.eleccion, isNull);
        expect(resultado.cierres, 1);
      });

      for (final escala in [2.0, 3.0]) {
        testWidgets(
          'a 320×568 con el texto al ${(escala * 100).round()} % y el teclado abierto: no '
          'desborda y «Todavía no sé con quién» se alcanza',
          (tester) async {
            final repo = PersonaRepositorioFalso();
            final resultado = await montarConQuien(
              tester,
              repo: repo,
              escala: escala,
              tamano: const Size(320, 568),
            );
            tester.view.viewInsets = const FakeViewPadding(bottom: 250);
            await asentar(tester);
            await _escribir(tester, _nombre, 'María de los Ángeles Fernández de la Peña');

            expect(tester.takeException(), isNull);
            await _tocar(tester, _botonSinNombre);

            expect(tester.takeException(), isNull);
            expect(resultado.sinPersona, isTrue);
            expect(repo.recibidas, isEmpty);
          },
        );
      }

      testWidgets('el objetivo táctil mide al menos 48 dp y el texto cumple el contraste', (
        tester,
      ) async {
        await montarConQuien(tester);

        expect(tester.getSize(_botonSinNombre).height, greaterThanOrEqualTo(48));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    });
  });

  group('«Entrevista dada» sin nombre sigue el flujo de la visita', () {
    testWidgets('casa sin personas: «Todavía no sé con quién» entrega la entrevista SIN persona al '
        'destino y la visita sigue', (tester) async {
      final a = await montarQuePaso(tester, entrevistaDada: true);

      await elegir(tester, OpcionQuePaso.entrevistaDada);
      expect(find.text('¿Con quién es la entrevista?'), findsOneWidget);
      await _tocar(tester, _botonSinNombre);

      expect(a.enganches.entrevistas, hasLength(1));
      expect(a.enganches.entrevistas.single.persona, isNull, reason: 'no se inventa a nadie');
      expect(a.enganches.entrevistas.single.espacioId, 'esp-1');
      expect(a.resultados, [true]);
    });

    testWidgets('casa sin personas, con nombre: el destino recibe a la persona nueva', (
      tester,
    ) async {
      final a = await montarQuePaso(tester, entrevistaDada: true);

      await elegir(tester, OpcionQuePaso.entrevistaDada);
      await _escribir(tester, _nombre, 'Pedro');
      await _tocar(tester, _botonEmpezar);

      expect(a.enganches.entrevistas.single.persona, isNotNull);
      expect(a.resultados, [true]);
    });

    testWidgets('«Volver» desde «¿Con quién?» no llega al destino', (tester) async {
      final a = await montarQuePaso(tester, entrevistaDada: true);

      await elegir(tester, OpcionQuePaso.entrevistaDada);
      await _tocar(tester, _botonVolver);

      expect(a.enganches.entrevistas, isEmpty);
    });
  });

  group('Crear la casa no pide ningún nombre', () {
    for (final estado in EstadoAlta.values) {
      testWidgets('alta de la casa, «${estado.rotulo}»: ningún campo de nombre ni de persona', (
        tester,
      ) async {
        await abrirEn(tester, estado);

        expect(find.text('NOMBRE'), findsNothing);
        expect(find.text('APELLIDO (OPCIONAL)'), findsNothing);
        expect(find.textContaining('¿Quién vive'), findsNothing);
        expect(find.textContaining('Con quién'), findsNothing);
        expect(_campo(_nombre), findsNothing);
      });
    }
  });

  group('Hoja de la casa nueva: la pestaña Personas vacía', () {
    testWidgets('sin personas dice que no hay, que se puede dejar para después y ofrece «+ Agregar '
        'persona»', (tester) async {
      await _montar(tester);

      expect(find.byKey(ClavesHojaCasa.sinPersonas), findsOneWidget);
      expect(find.text('Todavía no hay personas acá.'), findsOneWidget);
      expect(find.byKey(ClavesHojaCasa.sinPersonasParaDespues), findsOneWidget);
      expect(find.text('Podés sumar a alguien ahora o dejarlo para después.'), findsOneWidget);
      expect(find.byKey(ClavesHojaCasa.agregarPersona), findsOneWidget);
    });

    testWidgets('en una casa dada de baja no se ofrece agregar ni dice «para después»', (
      tester,
    ) async {
      await _montar(tester, baja: true);

      expect(find.text('Todavía no hay personas acá.'), findsOneWidget);
      expect(find.byKey(ClavesHojaCasa.sinPersonasParaDespues), findsNothing);
      expect(find.byKey(ClavesHojaCasa.agregarPersona), findsNothing);
    });

    testWidgets('con personas ya no aparece el vacío', (tester) async {
      await _montar(tester, conPersona: true);

      expect(find.byKey(ClavesHojaCasa.sinPersonas), findsNothing);
      expect(find.byKey(ClavesHojaCasa.sinPersonasParaDespues), findsNothing);
    });

    for (final escala in [2.0, 3.0]) {
      testWidgets(
        'a 320×568 con el texto al ${(escala * 100).round()} %: no desborda y el enlace se '
        'alcanza',
        (tester) async {
          await _montar(tester, escala: escala, tamano: const Size(320, 568));

          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(ClavesHojaCasa.agregarPersona));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byKey(ClavesHojaCasa.agregarPersona).hitTestable(), findsOneWidget);
        },
      );
    }
  });

  group('Hoja de la casa nueva: «+ Agregar persona» → nombre → «Guardar persona»', () {
    testWidgets(
      'con solo el nombre alcanza: tres toques y el teclado, a la persona la guarda en el '
      'espacio de la casa y la hoja lo dice',
      (tester) async {
        final m = await _montar(tester);

        // Toque 1: «+ Agregar persona».
        await tester.tap(find.byKey(ClavesHojaCasa.agregarPersona));
        await asentar(tester);
        expect(find.byType(AltaPersonaPage), findsOneWidget);
        // Toque 2 (y el teclado): el nombre. Toque 3: «Guardar persona».
        await _escribir(tester, _nombre, 'Jorge');
        await tester.tap(find.widgetWithText(FilledButton, 'Guardar persona'));
        await asentar(tester);

        expect(find.byType(AltaPersonaPage), findsNothing);
        expect(m.repo.recibidas, hasLength(1));
        final alta = m.repo.recibidas.single;
        expect(alta.persona.nombre, 'Jorge');
        expect(alta.persona.apellido, '');
        expect(alta.persona.telefono, isNull);
        expect(alta.nota, isNull);
        expect(alta.vinculo.espacioId, 'esp-1');
        expect(find.text('Guardamos a Jorge en este teléfono.'), findsOneWidget);
      },
    );

    testWidgets('el alta corta muestra el aviso de privacidad y el nombre como único obligatorio', (
      tester,
    ) async {
      await _montar(tester);

      await tester.tap(find.byKey(ClavesHojaCasa.agregarPersona));
      await asentar(tester);

      expect(
        find.text('Estos datos solo viven en tu celular. Nunca se suben a la nube.'),
        findsOneWidget,
      );
      expect(find.text('NOMBRE'), findsOneWidget);
      expect(find.text('APELLIDO (OPCIONAL)'), findsOneWidget);
      expect(find.text('TELÉFONO (OPCIONAL)'), findsOneWidget);
    });

    testWidgets('sin nombre no guarda y dice qué falta; el apellido y el teléfono vacíos no '
        'molestan', (tester) async {
      final m = await _montar(tester);
      await tester.tap(find.byKey(ClavesHojaCasa.agregarPersona));
      await asentar(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar persona'));
      await asentar(tester);

      expect(m.repo.recibidas, isEmpty);
      expect(find.byType(AltaPersonaPage), findsOneWidget);
      expect(find.text('TELÉFONO (OPCIONAL)'), findsOneWidget);
    });

    testWidgets('dejarlo para después: cerrar el alta no guarda a nadie y la hoja sigue igual', (
      tester,
    ) async {
      final m = await _montar(tester);
      await tester.tap(find.byKey(ClavesHojaCasa.agregarPersona));
      await asentar(tester);

      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);

      expect(m.repo.recibidas, isEmpty);
      expect(find.byKey(ClavesHojaCasa.sinPersonas), findsOneWidget);
      expect(find.byKey(ClavesHojaCasa.personaGuardada), findsNothing);
    });
  });
}

/// Lo que un test necesita después de montar la hoja.
final class _Montaje {
  final repo = PersonaRepositorioFalso();
}

/// La hoja de la casa recién creada (sin personas) o, con [conPersona], con una persona cargada.
Future<_Montaje> _montar(
  WidgetTester tester, {
  bool baja = false,
  bool conPersona = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  final m = _Montaje();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final contexto = ContextoDeLaCasa(
    espacioId: 'esp-1',
    personas: conPersona ? [pedroGomez] : const [],
  );
  final overrides = <Override>[
    ...overridesHojaCasa(lectura: (_) => Stream.value(contexto), registrarVisita: (_) {}),
    personaRepositoryProvider.overrideWithValue(m.repo),
    espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(contextoActivo())),
  ];
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: itemDeLaHoja(baja: baja ? DateTime.utc(2026, 10, 1) : null),
              ahora: ahoraLista,
              alCerrar: () {},
              arriba: true,
              colportorId: 'col-1',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return m;
}

// QA de #142 / PR #483 (vista 32C «Editar persona», HU-UBI-010): lo que los tests de la vista no
// miran: las guías de accesibilidad de Flutter (tamaño de toque, etiqueta, contraste) en cada estado,
// los dos teléfonos de referencia (360×640 y 412×915) con el texto al 100 % y al 200 %, el error de
// guardado con el teclado abierto, el orden del foco, las regiones vivas de cada aviso, la validación
// del teléfono con basura, el atrás del sistema con un guardado en curso y la privacidad de los
// `toString()`.
//
// Sin las fuentes reales a propósito: `textContrastGuideline` da falsos negativos con ellas (mide el
// contraste sobre el pixel de la captura y con la letra real el antialias baja la nota).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/modificar_persona_use_case.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_persona_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';

const _guardar = 'Guardar cambios';
const _guardarIgual = 'Guardar igual';
const _nombre = 'Obligatorio';
const _apellido = 'Apellido';
const _telefono = '09X XXX XXX';
const _noPudimos = 'No pudimos guardar a la persona. Probá de nuevo.';

const _telefono360 = Size(360, 640);
const _telefono412 = Size(412, 915);

Finder _campo(String sugerencia) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == sugerencia);

Future<void> _escribir(WidgetTester tester, String sugerencia, String texto) async {
  await tester.enterText(_campo(sugerencia), texto);
  await tester.pump();
}

Finder _boton(String etiqueta) => find.widgetWithText(FilledButton, etiqueta);

Future<void> _tocar(WidgetTester tester, String etiqueta) async {
  await tester.tap(_boton(etiqueta));
  await asentar(tester);
}

Future<void> _cambioTotal(WidgetTester tester) async {
  await _escribir(tester, _nombre, 'Roberto');
  await _escribir(tester, _apellido, 'Suárez');
  await _escribir(tester, _telefono, '091 222 333');
}

/// Cada estado de la vista, con la forma de llegar a él.
enum _Estado {
  cargando('cargando'),
  errorDeLectura('error de lectura'),
  personaQueYaNoEsta('la persona ya no está'),
  soloLectura('solo lectura (persona de baja)'),
  c01Editar('C·01 editar'),
  c02NombreVacio('C·02 nombre vacío'),
  c03OtraPersona('C·03 ¿es otra persona?'),
  errorAlGuardar('error al guardar'),
  descartar('¿descartar lo que escribiste?'),
  c04Guardado('C·04 guardado');

  const _Estado(this.rotulo);

  final String rotulo;
}

Future<void> _llegarA(
  WidgetTester tester,
  _Estado estado, {
  Size? tamano,
  double escala = 1,
}) async {
  final repo = PersonaRepositorioFalso();
  final t = tamano ?? _telefono360;
  switch (estado) {
    case _Estado.cargando:
      repo.compuertaLeer = Completer<void>();
      addTearDown(() {
        if (!repo.compuertaLeer!.isCompleted) repo.compuertaLeer!.complete();
      });
      await montarEdicion(tester, repo: repo, tamano: t, escala: escala);
    case _Estado.errorDeLectura:
      repo.fallaAlLeerParaEditar = const FailureInesperado(causa: 'x');
      await montarEdicion(tester, repo: repo, tamano: t, escala: escala);
    case _Estado.personaQueYaNoEsta:
      await montarEdicion(tester, repo: repo, tamano: t, escala: escala, abrir: false);
      repo.contextos.clear();
      await tester.tap(find.text('abrir edición'));
      await asentar(tester);
    case _Estado.soloLectura:
      repo.contextos['per-1'] = contextoDeEdicion(
        causa: CausaSoloLectura.personaDeBaja,
        bajaDesde: DateTime.utc(2026, 10, 22, 15),
      );
      await montarEdicion(tester, repo: repo, tamano: t, escala: escala);
    case _Estado.c01Editar:
      await montarEdicion(tester, repo: repo, tamano: t, escala: escala);
    case _Estado.c02NombreVacio:
      await montarEdicion(tester, repo: repo, tamano: t, escala: escala);
      await _escribir(tester, _nombre, '');
    case _Estado.c03OtraPersona:
      await montarEdicion(tester, repo: repo, tamano: t, escala: escala);
      await _cambioTotal(tester);
    case _Estado.errorAlGuardar:
      repo.resultadosModificar.add(const FailureInesperado(causa: 'x'));
      await montarEdicion(tester, repo: repo, tamano: t, escala: escala);
      await _escribir(tester, _telefono, '099 000 111');
      await _tocar(tester, _guardar);
    case _Estado.descartar:
      await montarEdicion(tester, repo: repo, tamano: t, escala: escala);
      await _escribir(tester, _telefono, '099 000 111');
      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);
    case _Estado.c04Guardado:
      await montarEdicion(tester, repo: repo, tamano: t, escala: escala);
      await _escribir(tester, _telefono, '099 000 111');
      await _tocar(tester, _guardar);
  }
}

void main() {
  group('QA #483 · guías de accesibilidad de Flutter en cada estado', () {
    for (final estado in _Estado.values) {
      for (final (tamano, escala) in [
        (_telefono360, 1.0),
        (_telefono360, 2.0),
        (_telefono412, 1.0),
        (_telefono412, 2.0),
      ]) {
        // QA #142 (hallazgo 1, arreglado por la decisión P1 del 11/11): con el aviso de error fijo
        // abajo, al 200 % en 360×640 el formulario quedaba en una ventana de ~150 px y «No volver a
        // mostrar» se medía como 260×13 (guía de toque).
        final documentaHallazgo =
            estado == _Estado.errorAlGuardar && tamano == _telefono360 && escala == 2.0;
        testWidgets('${documentaHallazgo ? 'QA #142: ' : ''}${estado.rotulo} · '
            '${tamano.width.toInt()}×${tamano.height.toInt()} · ${(escala * 100).toInt()} %', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await _llegarA(tester, estado, tamano: tamano, escala: escala);

          expect(tester.takeException(), isNull, reason: 'sin overflow');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }
  });

  group('QA #483 · el error de guardado con el teclado abierto', () {
    for (final escala in [1.0, 2.0]) {
      // QA #142 (hallazgo 1): al 200 % el aviso fijo + el botón no entraban sobre el teclado.
      testWidgets(
        '${escala == 2.0 ? 'QA #142: ' : ''}360×640 · ${(escala * 100).toInt()} % · aviso rojo y '
        '«Reintentar» a la vista, sin overflow',
        (tester) async {
          await _llegarA(tester, _Estado.errorAlGuardar, escala: escala);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          addTearDown(tester.view.resetViewInsets);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(tester.takeException(), isNull);
          expect(find.text(_noPudimos), findsOneWidget);
          expect(_boton('Reintentar'), findsOneWidget);
          final boton = tester.getRect(_boton('Reintentar'));
          expect(boton.bottom, lessThanOrEqualTo(640 - 280 + 0.5), reason: 'sobre el teclado');
          expect(boton.top, greaterThanOrEqualTo(0));
        },
      );
    }

    testWidgets('QA #142: 360×640 · 200 % · el aviso largo de «solo lectura» al guardar, sin '
        'overflow', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..resultadosModificar.add(
          FailureValidacion(campos: {'persona': MotivoRechazoPersona.personaSoloLectura.mensaje}),
        );
      await montarEdicion(tester, repo: repo, tamano: _telefono360, escala: 2);
      await _escribir(tester, _telefono, '099 000 111');
      await _tocar(tester, _guardar);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(_boton('Reintentar'), findsOneWidget);
    });
  });

  group('QA #483 · lector de pantalla y foco', () {
    testWidgets('el aviso rojo de «No pudimos guardar a la persona» es una región viva', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _llegarA(tester, _Estado.errorAlGuardar);

      final nodo = tester.getSemantics(find.text(_noPudimos));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('el aviso de error de lectura es una región viva y «Reintentar» es un botón', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _llegarA(tester, _Estado.errorDeLectura);

      final nodo = tester.getSemantics(
        find.text('No pudimos leer los datos de la persona en tu teléfono.'),
      );
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      final reintentar = tester.getSemantics(find.text('Reintentar'));
      expect(reintentar.flagsCollection.isButton, isTrue);
      expect(reintentar.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('el aviso de solo lectura y el de «ya no está» son regiones vivas', (tester) async {
      final handle = tester.ensureSemantics();
      await _llegarA(tester, _Estado.soloLectura);

      final nodo = tester.getSemantics(find.textContaining('Sus datos no se pueden editar.'));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('con Tab el foco recorre nombre, apellido y teléfono, en ese orden', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.c01Editar);
      await tester.tap(_campo(_nombre));
      await tester.pump();
      bool tiene(String s) => tester.widget<TextField>(_campo(s)).focusNode!.hasFocus;
      expect(tiene(_nombre), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tiene(_apellido), isTrue);

      // Entre el apellido y el teléfono hay una parada intermedia del foco (un `Focus` sin campo).
      for (var i = 0; i < 3 && !tiene(_telefono); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(tiene(_telefono), isTrue);
    });
  });

  group('QA #483 · validación del teléfono con basura', () {
    for (final (texto, mensaje) in [
      ('abc', 'Revisá el teléfono: solo puede tener números, espacios y un + al comienzo.'),
      ('099 12😀', 'Revisá el teléfono: solo puede tener números, espacios y un + al comienzo.'),
      ('099 123 4567', 'Revisá el teléfono: le sobran números.'),
      ('099 1', 'Revisá el teléfono: le faltan números.'),
    ]) {
      testWidgets('«$texto»: al guardar avisa, no escribe, conserva lo tipeado y lleva el foco', (
        tester,
      ) async {
        final repo = PersonaRepositorioFalso();
        await montarEdicion(tester, repo: repo);

        await _escribir(tester, _telefono, texto);
        await _tocar(tester, _guardar);

        expect(find.text(mensaje), findsOneWidget);
        expect(repo.editadas, isEmpty);
        expect(find.text(texto), findsOneWidget);
        expect(tester.widget<TextField>(_campo(_telefono)).focusNode!.hasFocus, isTrue);
      });
    }

    testWidgets('un nombre de solo espacios cuenta como vacío: avisa y no escribe', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _nombre, '     ');
      await _tocar(tester, _guardar);

      expect(find.text('El nombre no puede quedar vacío.'), findsOneWidget);
      expect(repo.editadas, isEmpty);
    });
  });

  group('QA #483 · C·03 con el criterio real y el texto del canvas', () {
    testWidgets('el aviso dice, letra por letra, lo que dibuja 32C·03 y ofrece «Guardar igual»', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.c03OtraPersona);

      expect(
        find.text(
          'Cambiaste nombre, apellido y teléfono. Si es otra persona, conviene dar de baja a '
          'María y registrar a Roberto aparte, para no mezclar el historial.',
        ),
        findsOneWidget,
      );
      expect(find.text('Dar de baja y crear nueva'), findsOneWidget);
      expect(_boton(_guardarIgual), findsOneWidget);
    });

    testWidgets('«maría» → «Maria» y «Fernandez» → «Fernández» a la vez: ni mayúsculas ni tildes '
        'cuentan, no hay aviso', (tester) async {
      await _llegarA(tester, _Estado.c01Editar);

      await _escribir(tester, _nombre, 'maria');
      await _escribir(tester, _apellido, 'fernandez');

      expect(find.text('Dar de baja y crear nueva'), findsNothing);
      expect(_boton(_guardar), findsOneWidget);
    });

    testWidgets('una persona sin apellido a la que se le completa nombre y apellido: sin aviso', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso()
        ..contextos['per-1'] = contextoDeEdicion(apellido: '', telefono: null);
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _nombre, 'Roberto');
      await _escribir(tester, _apellido, 'Suárez');

      expect(find.text('Dar de baja y crear nueva'), findsNothing);
    });

    testWidgets(
      '«Guardar igual» después de un cambio total guarda y la ficha ve la persona nueva',
      (tester) async {
        final repo = PersonaRepositorioFalso();
        final resultado = await montarEdicion(tester, repo: repo);
        await _cambioTotal(tester);

        await _tocar(tester, _guardarIgual);

        expect(repo.editadas.single.nombre, 'Roberto');
        expect(repo.editadas.single.apellido, 'Suárez');
        expect(resultado.resultado, isA<PersonaEditada>());
        expect(resultado.cierres, 1);
      },
    );
  });

  group('QA #483 · acciones superpuestas', () {
    testWidgets('el atrás del sistema con un guardado en curso no cierra ni pregunta; al terminar '
        'cierra una sola vez con la persona', (tester) async {
      final repo = PersonaRepositorioFalso()..compuertaModificar = Completer<void>();
      final resultado = await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');
      await tester.tap(_boton(_guardar));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(find.text('Editar persona'), findsOneWidget);
      expect(find.text('¿Descartar lo que escribiste?'), findsNothing);
      expect(resultado.cierres, 0);

      repo.compuertaModificar!.complete();
      await asentar(tester);

      expect(resultado.cierres, 1);
      expect(resultado.resultado, isA<PersonaEditada>());
      expect(repo.editadas, hasLength(1));
    });

    testWidgets('un guardado en curso deja «Guardando…» y bloquea la ✕; si falla, todo vuelve', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso()
        ..compuertaModificar = Completer<void>()
        ..resultadosModificar.add(const FailureInesperado(causa: 'x'));
      await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');
      await tester.tap(_boton(_guardar));
      await tester.pump();

      expect(find.text('Guardando…'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);

      repo.compuertaModificar!.complete();
      await asentar(tester);

      expect(find.text('Guardando…'), findsNothing);
      expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNotNull);
      expect(_boton('Reintentar'), findsOneWidget);
    });
  });

  group('QA #483 · privacidad', () {
    test('ni los parámetros, ni el contexto, ni los resultados, ni las fallas llevan datos '
        'personales en su toString()', () {
      final contexto = contextoDeEdicion();
      final cosas = <Object>[
        const ModificarPersonaParams(
          personaId: 'per-1',
          nombre: 'María',
          apellido: 'Fernández',
          telefono: '098 765 432',
        ),
        contexto,
        contexto.persona,
        PersonaEditada(contexto.persona),
        DarDeBajaYCrearNuevaElegido(
          original: contexto.persona,
          nombre: 'Roberto',
          apellido: 'Suárez',
          telefono: '091 222 333',
        ),
        FailureValidacion(campos: {'persona': MotivoRechazoPersona.personaSoloLectura.mensaje}),
        const FailureInesperado(causa: 'StateError'),
      ];
      for (final c in cosas) {
        final texto = c.toString();
        for (final dato in ['María', 'Fernández', '098', '765', 'Roberto', 'Suárez', '091']) {
          expect(texto, isNot(contains(dato)), reason: '${c.runtimeType}.toString() → $texto');
        }
      }
    });
  });

  group('QA #483 · hallazgos', () {
    testWidgets(
      'QA #142: dado que la persona se dio de baja con la edición abierta, cuando guarda, el aviso no '
      'culpa al espacio y no ofrece un «Reintentar» que repite el mismo error',
      (tester) async {
        final repo = PersonaRepositorioFalso()
          ..resultadosModificar.add(
            FailureValidacion(campos: {'persona': MotivoRechazoPersona.personaSoloLectura.mensaje}),
          );
        await montarEdicion(tester, repo: repo);
        await _escribir(tester, _telefono, '099 000 111');
        // Mientras tanto, la persona se dio de baja (la causa es la persona, no el espacio).
        repo.contextos['per-1'] = contextoDeEdicion(
          causa: CausaSoloLectura.personaDeBaja,
          bajaDesde: DateTime.utc(2026, 10, 22, 15),
        );

        await _tocar(tester, _guardar);

        expect(find.textContaining('Su espacio está dado de baja'), findsNothing);
        expect(_boton('Reintentar'), findsNothing);
      },
      // QA #142 (hallazgo 2): el aviso decía «Su espacio está dado de baja» (causa equivocada) y
      // dejaba «Reintentar», que repetía el error. Ahora se relee a la persona.
    );
  });
}

// HU-UBI-008 / vista 32A «Alta de persona» (A·01 a A·06) y los casos límite de cada flujo: doble toque,
// falla a mitad del guardado, reintento, volver atrás y reentrar, textos largos y texto al 200 %.
// No hay estado «sin conexión»: el alta es solo local.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';

const _guardar = 'Guardar persona';
const _nombre = 'Obligatorio';
const _apellido = 'Apellido';
const _telefono = '09X XXX XXX';
const _nota = 'Lo que te sirva para la próxima visita';

Finder _campo(String sugerencia) => find.widgetWithText(TextField, sugerencia).hitTestable();

Future<void> _escribir(WidgetTester tester, String sugerencia, String texto) async {
  await tester.enterText(
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == sugerencia),
    texto,
  );
  await tester.pump();
}

Future<void> _tocarGuardar(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, _guardar));
  await asentar(tester);
}

double _contraste(Color a, Color b) {
  final (mayor, menor) = a.computeLuminance() > b.computeLuminance() ? (a, b) : (b, a);
  return (mayor.computeLuminance() + 0.05) / (menor.computeLuminance() + 0.05);
}

void main() {
  group('A·01 · formulario completo', () {
    testWidgets('dado el formulario vacío, cuando se abre, muestra el candado, los cuatro campos '
        'con sus textos y el botón', (tester) async {
      await montarAlta(tester);

      expect(find.text('NUEVA PERSONA'), findsOneWidget);
      expect(find.text('Nueva persona'), findsOneWidget);
      expect(find.text('Mataojo 2044 · Depto 101'), findsOneWidget);
      expect(
        find.text('Estos datos solo viven en tu celular. Nunca se suben a la nube.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('NOMBRE'), findsOneWidget);
      expect(find.text('APELLIDO (OPCIONAL)'), findsOneWidget);
      expect(find.text('TELÉFONO (OPCIONAL)'), findsOneWidget);
      expect(find.text('PRIMERA NOTA (OPCIONAL)'), findsOneWidget);
      for (final s in [_nombre, _apellido, _telefono, _nota]) {
        expect(_campo(s), findsOneWidget);
      }
      expect(find.widgetWithText(FilledButton, _guardar), findsOneWidget);
      expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsNothing);
    });

    testWidgets(
      'dado nombre, apellido, teléfono y nota, cuando toca «Guardar persona», guarda todo '
      'y vuelve con la persona',
      (tester) async {
        final repo = PersonaRepositorioFalso();
        final resultado = await montarAlta(tester, repo: repo);

        await _escribir(tester, _nombre, 'Ana');
        await _escribir(tester, _apellido, 'Martínez');
        await _escribir(tester, _telefono, '099 123 456');
        await _escribir(tester, _nota, 'Prefiere de tarde');
        await _tocarGuardar(tester);

        final alta = repo.recibidas.single;
        expect(alta.persona.nombre, 'Ana');
        expect(alta.persona.apellido, 'Martínez');
        expect(alta.persona.telefono, '099 123 456');
        expect(alta.nota?.texto, 'Prefiere de tarde');
        expect(alta.vinculo.espacioId, 'esp-1');
        expect(alta.persona.auditoria.createdBy, 'col-1');
        expect(resultado.persona?.nombre, 'Ana');
        expect(find.text('Nueva persona'), findsNothing);
      },
    );
  });

  group('A·02 · solo el nombre', () {
    testWidgets('dado solo el nombre, cuando guarda, el apellido queda vacío y no hay teléfono ni '
        'nota', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(tester, repo: repo);

      await _escribir(tester, _nombre, 'Jorge');
      await _tocarGuardar(tester);

      final alta = repo.recibidas.single;
      expect(alta.persona.nombre, 'Jorge');
      expect(alta.persona.apellido, '');
      expect(alta.persona.telefono, isNull);
      expect(alta.nota, isNull);
    });
  });

  group('A·02B · con primera nota', () {
    testWidgets(
      'dado el nombre y una primera nota, cuando guarda, la nota viaja atada a la persona',
      (tester) async {
        final repo = PersonaRepositorioFalso();
        await montarAlta(tester, repo: repo);

        await _escribir(tester, _nombre, 'Ana');
        await _escribir(tester, _nota, 'Tiene perro, tocar el timbre dos veces');
        await _tocarGuardar(tester);

        final alta = repo.recibidas.single;
        expect(alta.nota?.texto, 'Tiene perro, tocar el timbre dos veces');
        expect(alta.nota?.personaId, alta.persona.id);
      },
    );

    testWidgets('dado una nota muy larga con renglones, cuando guarda, se guarda entera', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(tester, repo: repo);
      final larga = List.generate(300, (i) => 'renglón $i de la nota').join('\n');

      await _escribir(tester, _nombre, 'Ana');
      await _escribir(tester, _nota, larga);
      await _tocarGuardar(tester);

      expect(repo.recibidas.single.nota?.texto, larga);
    });
  });

  group('A·03 · nombre vacío', () {
    testWidgets('dado el nombre vacío, cuando toca «Guardar persona», muestra «Escribí al menos el '
        'nombre.», no guarda y deja el foco en el nombre', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(tester, repo: repo);

      await _tocarGuardar(tester);

      expect(find.text('Escribí al menos el nombre.'), findsOneWidget);
      expect(repo.recibidas, isEmpty);
      final nombre = tester.widget<TextField>(
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == _nombre),
      );
      expect(nombre.focusNode?.hasFocus, isTrue);
      expect(find.widgetWithText(FilledButton, _guardar), findsOneWidget);
    });

    testWidgets('dado que se dejó el nombre vacío sin tocar el botón, cuando el foco pasa a otro '
        'campo, el error aparece', (tester) async {
      await montarAlta(tester);

      await tester.tap(_campo(_nombre));
      await tester.pump();
      await tester.tap(_campo(_apellido));
      await tester.pump();

      expect(find.text('Escribí al menos el nombre.'), findsOneWidget);
    });

    testWidgets('dado el error del nombre, cuando se escribe el nombre, el error se va', (
      tester,
    ) async {
      await montarAlta(tester);
      await _tocarGuardar(tester);

      await _escribir(tester, _nombre, 'Ana');

      expect(find.text('Escribí al menos el nombre.'), findsNothing);
    });

    testWidgets('dado un nombre de una letra, cuando toca guardar, dice que necesita 2 letras', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(tester, repo: repo);

      await _escribir(tester, _nombre, 'A');
      await _tocarGuardar(tester);

      expect(find.text('El nombre necesita al menos 2 letras.'), findsOneWidget);
      expect(repo.recibidas, isEmpty);
    });

    testWidgets(
      'dado el botón apagado a la vista, cuando se mide, el texto cumple el contraste AA',
      (tester) async {
        await montarAlta(tester);

        final boton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, _guardar));
        final fondo = boton.style!.backgroundColor!.resolve({})!;
        final texto = boton.style!.foregroundColor!.resolve({})!;
        expect(_contraste(fondo, texto), greaterThanOrEqualTo(4.5));
      },
    );
  });

  group('A·04 · teléfono incompleto', () {
    testWidgets('dado «099 12», cuando toca guardar, dice «Revisá el teléfono: le faltan números.» '
        'y no guarda', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(tester, repo: repo);

      await _escribir(tester, _nombre, 'Ana');
      await _escribir(tester, _telefono, '099 12');
      await _tocarGuardar(tester);

      expect(find.text('Revisá el teléfono: le faltan números.'), findsOneWidget);
      expect(repo.recibidas, isEmpty);
      final telefono = tester.widget<TextField>(
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == _telefono),
      );
      expect(telefono.focusNode?.hasFocus, isTrue);
    });

    testWidgets(
      'dado el error del teléfono, cuando se completa el número, el error se va y guarda',
      (tester) async {
        final repo = PersonaRepositorioFalso();
        await montarAlta(tester, repo: repo);
        await _escribir(tester, _nombre, 'Ana');
        await _escribir(tester, _telefono, '099 12');
        await _tocarGuardar(tester);

        await _escribir(tester, _telefono, '099 123 456');
        expect(find.text('Revisá el teléfono: le faltan números.'), findsNothing);
        await _tocarGuardar(tester);

        expect(repo.recibidas.single.persona.telefono, '099 123 456');
      },
    );

    testWidgets('dado un teléfono con letras, cuando toca guardar, dice qué caracteres sirven', (
      tester,
    ) async {
      await montarAlta(tester);

      await _escribir(tester, _nombre, 'Ana');
      await _escribir(tester, _telefono, 'abc123');
      await _tocarGuardar(tester);

      expect(find.textContaining('solo puede tener números'), findsOneWidget);
    });

    testWidgets('dado un número del exterior con +, cuando guarda, no se bloquea', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(tester, repo: repo);

      await _escribir(tester, _nombre, 'Ana');
      await _escribir(tester, _telefono, '+54 9 11 5555 1234');
      await _tocarGuardar(tester);

      expect(repo.recibidas.single.persona.telefono, '+54 9 11 5555 1234');
    });
  });

  group('A·06 · error al guardar', () {
    testWidgets(
      'dado que guardar falla, cuando termina, muestra el aviso, conserva lo escrito y el '
      'botón pasa a «Reintentar», habilitado',
      (tester) async {
        final repo = PersonaRepositorioFalso(resultados: [const FailureInesperado(causa: 'x')]);
        await montarAlta(tester, repo: repo);
        await _escribir(tester, _nombre, 'Ana');
        await _escribir(tester, _nota, 'una nota');

        await _tocarGuardar(tester);

        expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, _guardar), findsNothing);
        final boton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Reintentar'));
        expect(boton.onPressed, isNotNull);
        expect(find.text('Ana'), findsOneWidget);
        expect(find.text('una nota'), findsOneWidget);
        expect(find.text('Guardando…'), findsNothing);
      },
    );

    testWidgets('dado que guardar falló, cuando toca «Reintentar» y sale bien, usa los mismos ids '
        'y vuelve con la persona (una sola)', (tester) async {
      final repo = PersonaRepositorioFalso(resultados: [const FailureInesperado(causa: 'x')]);
      final resultado = await montarAlta(tester, repo: repo);
      await _escribir(tester, _nombre, 'Ana');
      await _escribir(tester, _nota, 'una nota');
      await _tocarGuardar(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await asentar(tester);

      expect(repo.recibidas, hasLength(2));
      expect(repo.recibidas[1].persona.id, repo.recibidas[0].persona.id);
      expect(repo.recibidas[1].vinculo.id, repo.recibidas[0].vinculo.id);
      expect(repo.recibidas[1].nota!.id, repo.recibidas[0].nota!.id);
      expect(resultado.persona?.nombre, 'Ana');
      expect(resultado.cierres, 1);
      expect(find.text('Nueva persona'), findsNothing);
    });

    testWidgets(
      'dado que falla dos veces seguidas, cuando reintenta, el botón vuelve a habilitarse '
      'cada vez y nunca queda «Guardando…»',
      (tester) async {
        final repo = PersonaRepositorioFalso(
          resultados: [
            const FailureInesperado(causa: 'x'),
            const FailureInesperado(causa: 'y'),
          ],
        );
        await montarAlta(tester, repo: repo);
        await _escribir(tester, _nombre, 'Ana');
        await _tocarGuardar(tester);

        await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
        await asentar(tester);

        expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Reintentar')).onPressed,
          isNotNull,
        );
        expect(find.text('Guardando…'), findsNothing);
      },
    );

    testWidgets('dado que el espacio se dio de baja, cuando guarda, el aviso dice por qué', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso(
        resultados: [
          FailureValidacion(campos: {'espacio': MotivoRechazoPersona.espacioDeBaja.mensaje}),
        ],
      );
      await montarAlta(tester, repo: repo);
      await _escribir(tester, _nombre, 'Ana');

      await _tocarGuardar(tester);

      expect(find.text(MotivoRechazoPersona.espacioDeBaja.mensaje), findsOneWidget);
      expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsNothing);
    });

    testWidgets('dado que el caso de uso lanza una excepción con datos, cuando guarda, la pantalla '
        'muestra el aviso y no el detalle', (tester) async {
      final repo = _RepoQueLanza();
      await montarAlta(tester, repo: repo);
      await _escribir(tester, _nombre, 'Ana');

      await _tocarGuardar(tester);

      expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsOneWidget);
      expect(find.textContaining('099'), findsNothing);
    });
  });

  group('casos límite del guardado', () {
    testWidgets('dado un doble toque en «Guardar persona», cuando el guardado está en curso, solo '
        'se guarda una vez', (tester) async {
      final repo = PersonaRepositorioFalso()..compuerta = Completer<void>();
      final resultado = await montarAlta(tester, repo: repo);
      await _escribir(tester, _nombre, 'Ana');

      // Dos toques sin fotograma en el medio: el segundo llega antes de que el botón se apague.
      final boton = find.widgetWithText(FilledButton, _guardar);
      await tester.tap(boton);
      await tester.tap(boton);
      await tester.pump();

      expect(find.text('Guardando…'), findsOneWidget);
      expect(repo.recibidas, hasLength(1));

      repo.compuerta!.complete();
      await asentar(tester);

      expect(repo.recibidas, hasLength(1));
      expect(resultado.cierres, 1);
    });

    testWidgets(
      'dado un guardado en curso, cuando se intenta salir con «Cerrar» o con atrás, no se '
      'sale',
      (tester) async {
        final repo = PersonaRepositorioFalso()..compuerta = Completer<void>();
        await montarAlta(tester, repo: repo);
        await _escribir(tester, _nombre, 'Ana');
        await _tocarGuardar(tester);

        await tester.tap(find.byTooltip('Cerrar'), warnIfMissed: false);
        await tester.pump();
        final salio = await tester.binding.handlePopRoute();
        await tester.pump();

        expect(salio, isTrue);
        expect(find.text('Nueva persona'), findsOneWidget);

        repo.compuerta!.complete();
        await asentar(tester);
        expect(find.text('Nueva persona'), findsNothing);
      },
    );

    testWidgets(
      'dado un guardado en curso, cuando se intenta escribir, los campos están bloqueados',
      (tester) async {
        final repo = PersonaRepositorioFalso()..compuerta = Completer<void>();
        await montarAlta(tester, repo: repo);
        await _escribir(tester, _nombre, 'Ana');
        await _tocarGuardar(tester);

        final nombre = tester.widget<TextField>(
          find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == _nombre),
        );
        expect(nombre.readOnly, isTrue);

        repo.compuerta!.complete();
        await asentar(tester);
      },
    );

    testWidgets('dado que se cierra sin guardar y se vuelve a abrir, cuando reentra, el formulario '
        'está vacío y los ids son otros', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarAlta(tester, repo: repo);
      await _escribir(tester, _nombre, 'Ana');

      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);
      expect(resultado.persona, isNull);
      expect(resultado.cierres, 1);

      await tester.tap(find.text('abrir alta'));
      await asentar(tester);
      expect(find.text('Ana'), findsNothing);
      await _escribir(tester, _nombre, 'Bruno');
      await _tocarGuardar(tester);

      expect(repo.recibidas.single.persona.nombre, 'Bruno');
    });

    testWidgets('dado dos altas seguidas en el mismo espacio, cuando se guardan, son dos personas '
        'distintas', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(tester, repo: repo);
      await _escribir(tester, _nombre, 'Ana');
      await _tocarGuardar(tester);
      await tester.tap(find.text('abrir alta'));
      await asentar(tester);
      await _escribir(tester, _nombre, 'Bruno');
      await _tocarGuardar(tester);

      expect(repo.recibidas, hasLength(2));
      expect(repo.recibidas[1].persona.id, isNot(repo.recibidas[0].persona.id));
    });
  });

  group('datos límite y texto grande', () {
    testWidgets('dado el texto al 200 % y un error visible, cuando se muestra el formulario, no se '
        'desborda y el botón sigue a la vista y es tocable', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(tester, repo: repo, escala: 2);

      await _tocarGuardar(tester);
      expect(find.text('Escribí al menos el nombre.'), findsOneWidget);
      await _escribir(tester, _nombre, 'Ana');
      await _escribir(tester, _telefono, '099 12');
      await _tocarGuardar(tester);

      expect(tester.takeException(), isNull);
      final boton = find.widgetWithText(FilledButton, _guardar);
      expect(boton, findsOneWidget);
      expect(tester.getSize(boton).height, greaterThanOrEqualTo(52));
      expect(find.textContaining('le faltan números'), findsOneWidget);
    });

    testWidgets('dado el aviso de falla y el texto al 200 %, cuando se muestra, no se desborda', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso(resultados: [const FailureInesperado(causa: 'x')]);
      await montarAlta(tester, repo: repo, escala: 2, tamano: const Size(320, 640));
      await _escribir(tester, _nombre, 'Ana');
      await _tocarGuardar(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
    });

    testWidgets('dado un nombre y un apellido de más de 60 letras, cuando se pegan, se recortan al '
        'tope', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(tester, repo: repo);

      await _escribir(tester, _nombre, 'N' * 100);
      await _escribir(tester, _apellido, 'A' * 100);
      await _tocarGuardar(tester);

      expect(repo.recibidas.single.persona.nombre.length, 60);
      expect(repo.recibidas.single.persona.apellido.length, 60);
    });

    testWidgets('dado un nombre pegado con saltos de línea, cuando se guarda, queda en una línea', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(tester, repo: repo);

      await _escribir(tester, _nombre, 'Ana\nMaría');
      await _tocarGuardar(tester);

      expect(repo.recibidas.single.persona.nombre, isNot(contains('\n')));
    });

    testWidgets('dado un espacio que no se pudo leer, cuando se abre, el formulario igual funciona '
        'sin la dirección', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarAlta(
        tester,
        repo: repo,
        fallaDeContexto: const FailureInesperado(causa: 'x'),
      );
      await _escribir(tester, _nombre, 'Ana');
      await _tocarGuardar(tester);

      expect(repo.recibidas, hasLength(1));
    });
  });

  group('accesibilidad', () {
    testWidgets('dado el formulario, cuando se leen sus campos, cada uno tiene su nombre y el '
        'obligatorio lo dice', (tester) async {
      final handle = tester.ensureSemantics();
      await montarAlta(tester);

      expect(find.bySemanticsLabel(RegExp('NOMBRE, obligatorio')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('TELÉFONO')), findsWidgets);
      expect(tester.getSemantics(find.byTooltip('Cerrar')).getSemanticsData().tooltip, 'Cerrar');
      handle.dispose();
    });

    testWidgets('dado el botón «Cerrar», cuando se mide, es de al menos 48 × 48', (tester) async {
      await montarAlta(tester);

      final tamano = tester.getSize(find.byTooltip('Cerrar'));
      expect(tamano.width, greaterThanOrEqualTo(48));
      expect(tamano.height, greaterThanOrEqualTo(48));
    });
  });
}

/// Repositorio que lanza una excepción con datos personales adentro (la de Drift trae la sentencia).
final class _RepoQueLanza extends PersonaRepositorioFalso {
  @override
  Future<Either<Failure, Persona>> registrar({
    required Persona persona,
    required EspacioPersona vinculo,
    NotaPersona? nota,
  }) => throw StateError('INSERT INTO persona … 099 123 456');
}

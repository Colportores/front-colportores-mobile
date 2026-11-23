// Decisiones del 11/11 sobre el QA de #142 (PR #483, vista 32C «Editar persona»):
// - P1: el aviso rojo de la falla al guardar va dentro del contenido que se desplaza, arriba de los
//   campos (como 32A·06), y la pantalla lo trae a la vista al aparecer.
//   Al aparecer, el foco del lector de pantalla pasa al aviso, sin tocar el del teclado. «Reintentar»
//   queda en el botón de abajo, como en 32A·06 (el canvas A·06 no trae un enlace dentro del aviso).
// - P2: el aviso de «¿Es otra persona?» se trae a la vista la primera vez que aparece, sin sacarle el
//   foco al campo que se está escribiendo.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';

const _guardar = 'Guardar cambios';
const _nombre = 'Obligatorio';
const _apellido = 'Apellido';
const _telefono = '09X XXX XXX';
const _noPudimos = 'No pudimos guardar a la persona. Probá de nuevo.';
const _bajaYNueva = 'Dar de baja y crear nueva';

const _telefono360 = Size(360, 640);

Finder _campo(String sugerencia) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == sugerencia);

Future<void> _escribir(WidgetTester tester, String sugerencia, String texto) async {
  await tester.enterText(_campo(sugerencia), texto);
  await tester.pump();
}

Finder _aviso(String texto) =>
    find.ancestor(of: find.textContaining(texto), matching: find.byType(AvisoAlta));

/// El scroll vertical del formulario (los campos de texto tienen el suyo, horizontal).
final _scrollDelFormulario = find
    .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
    .first;

/// La parte de la pantalla donde se desplaza el formulario.
Rect _ventana(WidgetTester tester) => tester.getRect(_scrollDelFormulario);

/// Se ve entero o, si es más alto que la ventana (con la letra de prueba al 200 % pasa), se ve su
/// comienzo arriba de todo.
bool _seVeEntero(WidgetTester tester, Finder finder) {
  final ventana = _ventana(tester);
  final rect = tester.getRect(finder);
  if (rect.height > ventana.height) return (rect.top - ventana.top).abs() < 0.5;
  return rect.top >= ventana.top - 0.5 && rect.bottom <= ventana.bottom + 0.5;
}

void main() {
  group('P1 · el aviso de la falla al guardar, arriba de los campos', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('dado 360×640 al ${(escala * 100).toInt()} %, cuando guardar falla, entonces el '
          'aviso está dentro del scroll, arriba del nombre, y se ve entero', (tester) async {
        final repo = PersonaRepositorioFalso()
          ..resultadosModificar.add(const FailureInesperado(causa: 'x'));
        await montarEdicion(tester, repo: repo, tamano: _telefono360, escala: escala);
        await _escribir(tester, _telefono, '099 000 111');

        await tester.ensureVisible(find.widgetWithText(FilledButton, _guardar));
        await tester.tap(find.widgetWithText(FilledButton, _guardar));
        await asentar(tester);

        expect(tester.takeException(), isNull);
        final aviso = _aviso(_noPudimos);
        expect(aviso, findsOneWidget);
        expect(
          find.ancestor(of: aviso, matching: find.byType(SingleChildScrollView)),
          findsOneWidget,
          reason: 'dentro del contenido que se desplaza, no fijo abajo',
        );
        expect(tester.getRect(aviso).top, lessThan(tester.getRect(_campo(_nombre)).top));
        expect(_seVeEntero(tester, aviso), isTrue, reason: 'la pantalla lo trae a la vista');
        expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
        expect(find.text('099 000 111'), findsOneWidget, reason: 'lo escrito sigue ahí');
      });
    }
  });

  group('P1 · el foco del lector de pantalla al aviso de la falla', () {
    /// Los eventos de «foco» que la app le manda a la plataforma (TalkBack / VoiceOver).
    List<Map<Object?, Object?>> escucharFocos(WidgetTester tester) {
      final focos = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility,
        (mensaje) async {
          if (mensaje is Map && mensaje['type'] == 'focus') focos.add(mensaje);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        ),
      );
      return focos;
    }

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'dado 360×640 al ${(escala * 100).toInt()} % con el teclado abierto, cuando guardar falla, '
        'entonces el foco del lector va al aviso, el del teclado sigue en el campo, «Reintentar» '
        'es uno solo y no hay overflow',
        (tester) async {
          final semantica = tester.ensureSemantics();
          final focos = escucharFocos(tester);
          final repo = PersonaRepositorioFalso()
            ..resultadosModificar.add(const FailureInesperado(causa: 'x'));
          await montarEdicion(tester, repo: repo, tamano: _telefono360, escala: escala);
          await _escribir(tester, _telefono, '099 000 111');
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          addTearDown(tester.view.resetViewInsets);
          await tester.pump();
          expect(focos, isEmpty, reason: 'antes de la falla no se mueve el foco del lector');

          await tester.ensureVisible(find.widgetWithText(FilledButton, _guardar));
          await tester.tap(find.widgetWithText(FilledButton, _guardar));
          await asentar(tester);

          expect(tester.takeException(), isNull);
          final aviso = _aviso(_noPudimos);
          expect(aviso, findsOneWidget);
          expect(focos, hasLength(1), reason: 'una sola vez, al aparecer el aviso');
          expect(focos.single['nodeId'], tester.getSemantics(aviso).id);
          final telefono = tester.widget<TextField>(_campo(_telefono));
          expect(telefono.focusNode?.hasFocus, isTrue, reason: 'el teclado no pierde su campo');
          expect(find.text('Reintentar'), findsOneWidget, reason: 'sin un segundo «Reintentar»');
          expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
          semantica.dispose();
        },
      );
    }

    testWidgets(
      'dado que el aviso ya está, cuando un segundo guardado también falla, entonces el foco '
      'del lector vuelve a ir al aviso',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final focos = escucharFocos(tester);
        final repo = PersonaRepositorioFalso()
          ..resultadosModificar.addAll(const [
            FailureInesperado(causa: 'x'),
            FailureInesperado(causa: 'y'),
          ]);
        await montarEdicion(tester, repo: repo, tamano: _telefono360, escala: 2);
        await _escribir(tester, _telefono, '099 000 111');

        await tester.ensureVisible(find.widgetWithText(FilledButton, _guardar));
        await tester.tap(find.widgetWithText(FilledButton, _guardar));
        await asentar(tester);
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Reintentar'));
        await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
        await asentar(tester);

        expect(tester.takeException(), isNull);
        expect(focos, hasLength(2));
        expect(focos.last['nodeId'], tester.getSemantics(_aviso(_noPudimos)).id);
        semantica.dispose();
      },
    );
  });

  group('P2 · «¿Es otra persona?» a la vista al aparecer', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'dado 360×640 al ${(escala * 100).toInt()} %, cuando el cambio pasa a parecer otra '
        'persona, entonces el aviso se ve entero y el foco sigue en el apellido',
        (tester) async {
          await montarEdicion(tester, tamano: _telefono360, escala: escala);
          await _escribir(tester, _nombre, 'Roberto');

          await _escribir(tester, _apellido, 'Suárez');
          await asentar(tester);

          expect(tester.takeException(), isNull);
          final aviso = _aviso(_bajaYNueva);
          expect(aviso, findsOneWidget);
          expect(_seVeEntero(tester, aviso), isTrue);
          final apellido = tester.widget<TextField>(_campo(_apellido));
          expect(apellido.focusNode?.hasFocus, isTrue, reason: 'no le saca el foco al campo');
        },
      );
    }

    testWidgets(
      'dado que el aviso ya se trajo a la vista, cuando la persona vuelve a subir y sigue '
      'escribiendo, entonces no la vuelve a llevar abajo',
      (tester) async {
        await montarEdicion(tester, tamano: _telefono360);
        await _escribir(tester, _nombre, 'Roberto');
        await _escribir(tester, _apellido, 'Suárez');
        await asentar(tester);
        final scrollable = tester.state<ScrollableState>(_scrollDelFormulario);
        scrollable.position.jumpTo(0);
        await tester.pump();

        await _escribir(tester, _apellido, 'Suárezz');
        await asentar(tester);

        expect(scrollable.position.pixels, 0);
      },
    );
  });
}

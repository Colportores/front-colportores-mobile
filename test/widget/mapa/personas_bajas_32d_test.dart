// HU-UBI-011 / vista 32D, artboards 04 y 05: «Mostrar bajas» en los clientes del depto, la fila de una
// persona dada de baja con su fecha y su saldo, «Reactivar» y el aviso «Reactivamos a …»; y los
// estados que el canvas no dibuja (espacio de baja, error al leer las bajas, falla al reactivar) con sus
// casos límite (doble toque, dos reactivaciones seguidas, listas largas, textScaler 2.0, volver y reentrar).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'baja_persona_arnes.dart';
import 'hoja_con_quien_arnes.dart' show SaldosFalsos;
import 'personas_arnes.dart';

final _mostrar = find.widgetWithText(SwitchListTile, 'Mostrar bajas');
final _reactivar = find.widgetWithText(TextButton, 'Reactivar');

PersonaRepositorioFalso _conJorgeYMariaDeBaja() => PersonaRepositorioFalso()
  ..sembrar([
    clienteDePersonas('p1', 'Jorge', apellido: 'Fernández'),
    clienteDeBajaDePersonas('p2', 'María', apellido: 'Fernández', minutos: 1),
  ]);

/// Overrides: el reloj fijo (para la fecha de la baja) y, si se pide, los saldos.
List<Override> _extras({Map<String, int>? saldos}) => [
  relojPersonaProvider.overrideWithValue(() => ahoraBaja),
  if (saldos != null) saldosDePersonasProvider.overrideWithValue(SaldosFalsos(saldos)),
];

Future<void> _mostrarLasBajas(WidgetTester tester) async {
  await tester.tap(_mostrar);
  await asentar(tester);
}

void main() {
  group('32D·04 · ver bajas y reactivar', () {
    testWidgets('dado un depto con una persona activa y una de baja, cuando se abre, muestra a la '
        'activa y el interruptor «Mostrar bajas» apagado, sin la baja', (tester) async {
      await montarClientes(tester, repo: _conJorgeYMariaDeBaja(), otrosOverrides: _extras());

      expect(find.text('CLIENTES · 1'), findsOneWidget);
      expect(find.text('Jorge Fernández'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(_mostrar).value, isFalse);
      expect(find.text('María Fernández'), findsNothing);
      expect(_reactivar, findsNothing);
    });

    testWidgets(
      'cuando prende «Mostrar bajas», aparece la baja en gris con la fecha y «Reactivar»; '
      'las activas siguen',
      (tester) async {
        await montarClientes(tester, repo: _conJorgeYMariaDeBaja(), otrosOverrides: _extras());

        await _mostrarLasBajas(tester);

        expect(find.text('María Fernández'), findsOneWidget);
        expect(find.text('Baja el 22/10'), findsOneWidget);
        expect(find.text('MF'), findsOneWidget);
        expect(_reactivar, findsOneWidget);
        expect(find.text('Jorge Fernández'), findsOneWidget);
        expect(find.text('CLIENTES · 1'), findsOneWidget);
      },
    );

    testWidgets('con el saldo conocido, la baja lo dice: «Baja el 22/10 · saldo \$ 1.200»', (
      tester,
    ) async {
      await montarClientes(
        tester,
        repo: _conJorgeYMariaDeBaja(),
        otrosOverrides: _extras(saldos: {'p2': 120000}),
      );

      await _mostrarLasBajas(tester);

      expect(find.text('Baja el 22/10 · saldo \$ 1.200'), findsOneWidget);
    });

    testWidgets('con el saldo en cero o desconocido, no afirma nada: ni «\$ 0» ni «saldo»', (
      tester,
    ) async {
      await montarClientes(
        tester,
        repo: _conJorgeYMariaDeBaja(),
        otrosOverrides: _extras(saldos: {'p2': 0}),
      );

      await _mostrarLasBajas(tester);

      expect(find.text('Baja el 22/10'), findsOneWidget);
      expect(find.textContaining('saldo'), findsNothing);
    });

    testWidgets('si falla la lectura del saldo, la baja se ve igual, sin saldo', (tester) async {
      await montarClientes(
        tester,
        repo: _conJorgeYMariaDeBaja(),
        otrosOverrides: [
          relojPersonaProvider.overrideWithValue(() => ahoraBaja),
          saldosDePersonasProvider.overrideWithValue(SaldosFalsos(const {}, falla: true)),
        ],
      );

      await _mostrarLasBajas(tester);

      expect(find.text('Baja el 22/10'), findsOneWidget);
    });

    testWidgets('una baja de otro año lleva el año para no confundirla', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([clienteDeBajaDePersonas('p2', 'María', baja: DateTime.utc(2025, 10, 22, 15))]);
      await montarClientes(tester, repo: repo, otrosOverrides: _extras());

      await _mostrarLasBajas(tester);

      expect(find.text('Baja el 22/10/2025'), findsOneWidget);
    });

    testWidgets('sin personas de baja no hay interruptor', (tester) async {
      final repo = PersonaRepositorioFalso()..sembrar([clienteDePersonas('p1', 'Jorge')]);
      await montarClientes(tester, repo: repo, otrosOverrides: _extras());

      expect(_mostrar, findsNothing);
      expect(find.text('Mostrar bajas'), findsNothing);
    });

    testWidgets('con todas las personas de baja, el depto dice que no hay clientes y deja ver las '
        'bajas', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([clienteDeBajaDePersonas('p2', 'María', apellido: 'Fernández')]);
      await montarClientes(tester, repo: repo, otrosOverrides: _extras());

      expect(find.text('Todavía no hay clientes'), findsOneWidget);
      await _mostrarLasBajas(tester);
      expect(find.text('María Fernández'), findsOneWidget);
    });

    testWidgets('el lector de pantalla oye el nombre y la baja de la fila y «Reactivar» como botón '
        'aparte', (tester) async {
      final handle = tester.ensureSemantics();
      await montarClientes(
        tester,
        repo: _conJorgeYMariaDeBaja(),
        otrosOverrides: _extras(saldos: {'p2': 120000}),
      );
      await _mostrarLasBajas(tester);

      expect(
        find.bySemanticsLabel('María Fernández. Baja el 22/10 · saldo \$ 1.200'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Reactivar'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('32D·05 · reactivar', () {
    testWidgets('cuando toca «Reactivar», la persona vuelve a la lista, deja las bajas y el aviso '
        'dice que la reactivamos', (tester) async {
      final repo = _conJorgeYMariaDeBaja();
      await montarClientes(tester, repo: repo, otrosOverrides: _extras());
      await _mostrarLasBajas(tester);

      await tester.tap(_reactivar);
      await asentar(tester);

      expect(repo.reactivacionesRecibidas, ['p2']);
      expect(find.text('Reactivamos a María.'), findsOneWidget);
      expect(find.text('CLIENTES · 2'), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(_reactivar, findsNothing);
      expect(_mostrar, findsNothing);
    });

    testWidgets('dos toques seguidos en «Reactivar» la reactivan una sola vez', (tester) async {
      final repo = _conJorgeYMariaDeBaja()..compuertaReactivar = Completer<void>();
      await montarClientes(tester, repo: repo, otrosOverrides: _extras());
      await _mostrarLasBajas(tester);

      await tester.tap(_reactivar);
      await tester.tap(_reactivar, warnIfMissed: false);
      repo.compuertaReactivar!.complete();
      await asentar(tester);

      expect(repo.reactivacionesRecibidas, ['p2']);
    });

    testWidgets(
      'mientras se reactiva, el botón se cambia por «Reactivando…» y no se puede volver a '
      'tocar',
      (tester) async {
        final repo = _conJorgeYMariaDeBaja()..compuertaReactivar = Completer<void>();
        await montarClientes(tester, repo: repo, otrosOverrides: _extras());
        await _mostrarLasBajas(tester);

        await tester.tap(_reactivar);
        await tester.pump();

        expect(_reactivar, findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        repo.compuertaReactivar!.complete();
        await asentar(tester);
        expect(find.text('Reactivamos a María.'), findsOneWidget);
      },
    );

    testWidgets(
      'si falla, el aviso dice qué hacer, la persona sigue de baja y «Reactivar» vuelve a '
      'estar tocable',
      (tester) async {
        final repo = _conJorgeYMariaDeBaja()..resultadosReactivar.add(const FailureInesperado());
        await montarClientes(tester, repo: repo, otrosOverrides: _extras());
        await _mostrarLasBajas(tester);

        await tester.tap(_reactivar);
        await asentar(tester);

        expect(find.text('No pudimos reactivar a María. Probá de nuevo.'), findsOneWidget);
        expect(find.text('María Fernández'), findsOneWidget);
        expect(find.text('CLIENTES · 1'), findsOneWidget);
        expect(tester.widget<TextButton>(_reactivar).onPressed, isNotNull);

        await tester.tap(_reactivar);
        await asentar(tester);

        expect(repo.reactivacionesRecibidas, ['p2', 'p2']);
        expect(find.text('Reactivamos a María.'), findsOneWidget);
        expect(find.text('CLIENTES · 2'), findsOneWidget);
      },
    );

    testWidgets('si el repositorio dice qué pasó, el aviso lo repite', (tester) async {
      final repo = _conJorgeYMariaDeBaja()
        ..resultadosReactivar.add(
          const FailureValidacion(campos: {'persona': 'La persona ya no está en tu teléfono.'}),
        );
      await montarClientes(tester, repo: repo, otrosOverrides: _extras());
      await _mostrarLasBajas(tester);

      await tester.tap(_reactivar);
      await asentar(tester);

      expect(find.text('La persona ya no está en tu teléfono.'), findsOneWidget);
    });

    testWidgets(
      'dos reactivaciones seguidas, antes de que termine la primera, se hacen las dos sin '
      'pisarse',
      (tester) async {
        final repo = PersonaRepositorioFalso()
          ..sembrar([
            clienteDeBajaDePersonas('p2', 'María', minutos: 1),
            clienteDeBajaDePersonas(
              'p3',
              'Pedro',
              minutos: 2,
              baja: DateTime.utc(2026, 10, 20, 15),
            ),
          ])
          ..compuertaReactivar = Completer<void>();
        await montarClientes(tester, repo: repo, otrosOverrides: _extras());
        await _mostrarLasBajas(tester);
        expect(_reactivar, findsNWidgets(2));

        await tester.tap(_reactivar.first);
        await tester.pump();
        await tester.tap(_reactivar.first);
        await tester.pump();
        repo.compuertaReactivar!.complete();
        await asentar(tester);

        expect(repo.reactivacionesRecibidas, unorderedEquals(['p2', 'p3']));
        expect(find.text('CLIENTES · 2'), findsOneWidget);
        expect(find.text('María'), findsOneWidget);
        expect(find.text('Pedro'), findsOneWidget);
        expect(_mostrar, findsNothing);
      },
    );

    testWidgets('al volver atrás y reentrar, el interruptor empieza apagado y la persona sigue '
        'reactivada', (tester) async {
      final repo = _conJorgeYMariaDeBaja();
      await montarClientes(tester, repo: repo, otrosOverrides: _extras());
      await _mostrarLasBajas(tester);
      await tester.binding.handlePopRoute();
      await asentar(tester);

      await tester.tap(find.text('abrir clientes'));
      await asentar(tester);

      expect(tester.widget<SwitchListTile>(_mostrar).value, isFalse);
      expect(find.text('María Fernández'), findsNothing);
    });
  });

  group('estados que el canvas no dibuja', () {
    testWidgets('con el espacio dado de baja, las bajas se ven y no se reactivan', (tester) async {
      await montarClientes(
        tester,
        repo: _conJorgeYMariaDeBaja(),
        contexto: contextoActivo(espacioDeBaja: DateTime.utc(2026, 10, 24)),
        otrosOverrides: _extras(),
      );

      await _mostrarLasBajas(tester);

      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('Baja el 22/10'), findsOneWidget);
      expect(_reactivar, findsNothing);
    });

    testWidgets('si no se pueden leer las bajas, avisa y «Reintentar» las trae', (tester) async {
      final repo = _RepoQueNoLeeLasBajasLaPrimeraVez();
      await montarClientes(tester, repo: repo, otrosOverrides: _extras());

      expect(find.text('No pudimos leer las bajas en tu teléfono.'), findsOneWidget);
      expect(find.text('Jorge Fernández'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      expect(find.text('No pudimos leer las bajas en tu teléfono.'), findsNothing);
      expect(_mostrar, findsOneWidget);
    });

    testWidgets('con una lista larga de bajas, se desplaza y se reactiva la última', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([
          clienteDePersonas('p1', 'Jorge'),
          for (var i = 0; i < 40; i++)
            clienteDeBajaDePersonas(
              'b$i',
              'Persona$i',
              minutos: i + 1,
              baja: DateTime.utc(2026, 10, 1).add(Duration(hours: i)),
            ),
        ]);
      await montarClientes(tester, repo: repo, otrosOverrides: _extras());
      await _mostrarLasBajas(tester);

      await tester.dragUntilVisible(
        find.text('Persona39'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Reactivar').last);
      await asentar(tester);

      expect(repo.reactivacionesRecibidas, ['b39']);
    });

    testWidgets(
      'con el texto al 200 %, el nombre de un cliente activo no se corta con «…» (decisión P2 '
      'del QA)',
      (tester) async {
        final repo = PersonaRepositorioFalso()
          ..sembrar([
            clienteDePersonas('p1', 'Maximiliano Alejandro', apellido: 'Fernández de la Peña'),
          ]);
        await montarClientes(
          tester,
          repo: repo,
          otrosOverrides: _extras(),
          escala: 2,
          tamano: const Size(360, 640),
        );

        for (final e in find.byType(RichText).evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a la escala de siempre, el nombre de una fila sigue acotado a tres renglones', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([
          clienteDePersonas('p1', 'Maximiliano Alejandro', apellido: 'Fernández de la Peña'),
        ]);
      await montarClientes(tester, repo: repo, otrosOverrides: _extras());

      final nombre = tester.widget<Text>(find.text('Maximiliano Alejandro Fernández de la Peña'));
      expect(nombre.maxLines, 3);
    });

    testWidgets('con un nombre larguísimo y textScaler 2.0 a 320×568, la fila no desborda y '
        '«Reactivar» se alcanza', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([
          clienteDeBajaDePersonas(
            'p2',
            'Maximiliano Alejandro Bartolomé',
            apellido: 'Fernández de la Vega y Altamirano',
          ),
        ]);
      await montarClientes(
        tester,
        repo: repo,
        otrosOverrides: _extras(saldos: {'p2': 120000}),
        escala: 2,
        tamano: const Size(320, 568),
      );
      // A 2× el interruptor queda más abajo de lo que se ve: se baja hasta él.
      await tester.dragUntilVisible(_mostrar, find.byType(ListView), const Offset(0, -80));
      await _mostrarLasBajas(tester);

      await tester.dragUntilVisible(_reactivar, find.byType(ListView), const Offset(0, -80));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_reactivar, findsOneWidget);
      expect(tester.getSize(_reactivar).height, greaterThanOrEqualTo(48));
    });
  });
}

/// Las activas se leen siempre; las bajas fallan la primera vez y salen bien la segunda.
final class _RepoQueNoLeeLasBajasLaPrimeraVez extends PersonaRepositorioFalso {
  _RepoQueNoLeeLasBajasLaPrimeraVez() {
    sembrar([
      clienteDePersonas('p1', 'Jorge', apellido: 'Fernández'),
      clienteDeBajaDePersonas('p2', 'María', apellido: 'Fernández', minutos: 1),
    ]);
  }

  var _lecturas = 0;

  @override
  Stream<List<PersonaDelEspacio>> observarBajasDelEspacio(String espacioId) {
    _lecturas += 1;
    return _lecturas == 1
        ? Stream.error(StateError('no se pudo leer'))
        : super.observarBajasDelEspacio(espacioId);
  }
}

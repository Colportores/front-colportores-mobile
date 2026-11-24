// QA de la vista 32 (#405, PR #755): «Editar persona», «Agregar» teléfono y «Dar de baja y crear nueva»
// (R6) desde la ficha. Cada paso del camino (la edición con «¿Es otra persona?», el alta con lo
// escrito, la baja sin y con saldo, y los dos avisos finales) con las cuatro guías de accesibilidad,
// sin overflow y con la persona nueva intacta, en 360×640 y 412×915 con el texto al 100 % y al 200 %.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_editar_persona_desde_la_ficha.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'baja_persona_arnes.dart';
import 'personas_arnes.dart';

const _nombre = 'Obligatorio';
const _apellido = 'Apellido';
const _telefono = '09X XXX XXX';
const _guardarPersona = 'Guardar persona';
const _bajaYNueva = 'Dar de baja y crear nueva';
const _guardadaRoberto = 'Guardamos a Roberto en este teléfono.';
const _sinLaBaja =
    'Guardamos a Roberto, pero la baja de María no se hizo y sigue en el depto. Podés dar de baja a '
    'María desde su ficha.';

/// Lo que el flujo devolvió a la pantalla de arranque.
final class _Salida {
  var terminadas = 0;
  Object? error;
}

Finder _campo(String sugerencia) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == sugerencia);

Future<void> _escribir(WidgetTester tester, String sugerencia, String texto) async {
  await tester.enterText(_campo(sugerencia), texto);
  await tester.pump();
}

/// El canvas 32C·03: pasar de «María Fernández» a otra persona.
Future<void> _cambioTotal(WidgetTester tester) async {
  await _escribir(tester, _nombre, 'Roberto');
  await _escribir(tester, _apellido, 'Suárez');
  await _escribir(tester, _telefono, '091 222 333');
}

Future<void> _tocarBoton(WidgetTester tester, String etiqueta) async {
  final boton = find.widgetWithText(FilledButton, etiqueta);
  await tester.ensureVisible(boton);
  await tester.tap(boton);
  await asentar(tester);
}

Future<void> _tocarTexto(WidgetTester tester, String texto) async {
  final f = find.text(texto);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await asentar(tester);
}

/// Monta una pantalla con un botón que corre [FlujoEditarPersonaDesdeLaFicha.abrir] sobre `per-1`
/// (María Fernández, del espacio `esp-1`), con los dobles de personas y de cuentas, y lo toca.
Future<_Salida> _montar(
  WidgetTester tester,
  PersonaRepositorioFalso repo, {
  CuentasFalsas? cuentas,
  bool otraPersona = true,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
  bool sinSesion = false,
}) async {
  final salida = _Salida();
  repo.contextos.putIfAbsent('per-1', contextoDeEdicion);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personaRepositoryProvider.overrideWithValue(repo),
        espacioRepositoryProvider.overrideWithValue(
          EspacioRepositorioParaPersonas(contextoActivo()),
        ),
        criterioOtraPersonaProvider.overrideWithValue(
          CriterioOtraPersonaFijo(respuesta: otraPersona),
        ),
        cuentasDePersonasProvider.overrideWithValue(cuentas ?? CuentasFalsas()),
        relojPersonaProvider.overrideWithValue(() => relojDeEdicion),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  try {
                    await FlujoEditarPersonaDesdeLaFicha.abrir(context, (
                      personaId: 'per-1',
                      espacioId: 'esp-1',
                    ), colportorId: sinSesion ? null : 'col-1');
                  } on Object catch (e) {
                    salida.error = e;
                  }
                  salida.terminadas += 1;
                },
                child: const Text('editar'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) {
    await tester.tap(find.text('editar'));
    await asentar(tester);
  }
  return salida;
}

PersonaRepositorioFalso _repoConMaria() =>
    PersonaRepositorioFalso()
      ..sembrar([clienteDePersonas('per-1', 'María', apellido: 'Fernández')]);

enum _Paso {
  edicionOtraPersona,
  altaConLoEscrito,
  bajaSinSaldo,
  bajaConSaldo,
  avisoGuardada,
  avisoSinLaBaja,
}

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  group(
    'guías de accesibilidad y overflow en cada paso del camino «Dar de baja y crear nueva»',
    () {
      for (final paso in _Paso.values) {
        for (final tam in const [Size(360, 640), Size(412, 915)]) {
          for (final escala in const [1.0, 2.0]) {
            testWidgets(
              '${paso.name} · ${tam.width.toInt()}×${tam.height.toInt()} · texto $escala',
              (tester) async {
                final semantica = tester.ensureSemantics();
                final repo = _repoConMaria();
                await _montar(
                  tester,
                  repo,
                  tamano: tam,
                  escala: escala,
                  cuentas: paso == _Paso.bajaConSaldo
                      ? CuentasFalsas(cuenta: cuentaConSaldo)
                      : null,
                );
                await _cambioTotal(tester);
                if (paso != _Paso.edicionOtraPersona) {
                  await _tocarTexto(tester, _bajaYNueva);
                }
                if (paso.index >= _Paso.bajaSinSaldo.index) {
                  await _tocarBoton(tester, _guardarPersona);
                }
                if (paso == _Paso.bajaConSaldo) {
                  await _tocarBoton(tester, 'Dar de baja igual');
                }
                if (paso == _Paso.avisoGuardada) {
                  await _tocarBoton(tester, 'Dar de baja');
                }
                if (paso == _Paso.avisoSinLaBaja) {
                  await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
                  await asentar(tester);
                }

                expect(tester.takeException(), isNull, reason: 'sin overflow');
                if (paso == _Paso.avisoGuardada) {
                  expect(find.text(_guardadaRoberto), findsOneWidget);
                }
                if (paso == _Paso.avisoSinLaBaja) {
                  expect(find.text(_sinLaBaja), findsOneWidget);
                }
                await _guias(tester);
                semantica.dispose();
              },
            );
          }
        }
      }
    },
  );

  group('casos límite del camino', () {
    testWidgets('should not offer the new person phone empty when the old one had none', (
      tester,
    ) async {
      final repo = _repoConMaria();
      await _montar(tester, repo);
      await _escribir(tester, _nombre, 'Roberto');
      await _escribir(tester, _apellido, 'Suárez');
      await _escribir(tester, _telefono, '');
      await _tocarTexto(tester, _bajaYNueva);

      expect(tester.widget<TextField>(_campo(_telefono)).controller!.text, isEmpty);
      await _tocarBoton(tester, _guardarPersona);
      expect(repo.recibidas.single.persona.telefono, anyOf(isNull, isEmpty));
    });
  });
}

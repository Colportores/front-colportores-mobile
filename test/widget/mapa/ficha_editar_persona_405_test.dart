// HU-UBI-009 / vista 32 B, #405: «Editar persona» y «Agregar» teléfono de la ficha, y «Dar de baja y crear
// nueva» (canvas 32C·03, regla R6 del 26/10): la edición, el alta de la persona nueva con lo escrito y,
// solo después, la baja de la original. Casos límite de cada paso: cancelar el alta, la baja que no se
// hace, la falla del alta a mitad, doble toque, volver y reentrar y texto al 200 %. Todo es local: no hay
// estado «sin conexión».
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_editar_persona_desde_la_ficha.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ficha_persona_falsos.dart' show mariaDePrueba;
import '../../helpers/persona_falsos.dart';
import 'baja_persona_arnes.dart';
import 'ficha_persona_arnes.dart' show MundoFicha, montarFicha;
import 'personas_arnes.dart';

const _nombre = 'Obligatorio';
const _apellido = 'Apellido';
const _telefono = '09X XXX XXX';
const _guardarCambios = 'Guardar cambios';
const _guardarPersona = 'Guardar persona';
const _bajaYNueva = 'Dar de baja y crear nueva';
const _cambiosGuardados = 'Cambios guardados en tu teléfono.';
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

/// Pasa de «María» a «Roberto» y elige «Dar de baja y crear nueva»: queda el alta con lo escrito.
Future<void> _hastaElAlta(WidgetTester tester) async {
  await _cambioTotal(tester);
  await _tocarTexto(tester, _bajaYNueva);
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

void main() {
  group('«Editar persona» desde la ficha', () {
    testWidgets(
      'dado «Agregar» teléfono en la ficha, cuando se toca, el destino recibe la persona y '
      'el espacio desde el que se abrió la ficha',
      (tester) async {
        final m = MundoFicha(persona: mariaDePrueba(telefono: null))..conEdicion = true;
        await montarFicha(tester, m);

        await tester.tap(find.text(TextosFicha.agregarTelefono));
        await asentar(tester);

        expect(m.ediciones, ['per-1']);
        expect(m.espaciosDeEdicion, ['esp-1']);
      },
    );

    testWidgets(
      'dado un cambio sin «otra persona», cuando se guarda, vuelve con «Cambios guardados» '
      'y no abre el alta ni la baja',
      (tester) async {
        final repo = _repoConMaria();
        final salida = await _montar(tester, repo, otraPersona: false);

        await _escribir(tester, _telefono, '091 222 333');
        await _tocarBoton(tester, _guardarCambios);

        expect(repo.editadas.single.telefono, '091 222 333');
        expect(find.text(_cambiosGuardados), findsOneWidget);
        expect(find.text('Nueva persona'), findsNothing);
        expect(repo.bajasRecibidas, isEmpty);
        expect(repo.recibidas, isEmpty);
        expect(salida.terminadas, 1);
      },
    );

    testWidgets('dado que se cierra la edición sin guardar, cuando vuelve, no pasa nada y se puede '
        'reabrir', (tester) async {
      final repo = _repoConMaria();
      final salida = await _montar(tester, repo);

      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);
      expect(salida.terminadas, 1);
      expect(repo.editadas, isEmpty);
      expect(repo.bajasRecibidas, isEmpty);

      await tester.tap(find.text('editar'));
      await asentar(tester);
      expect(find.text('Editar persona'), findsOneWidget);
    });

    testWidgets('sin sesión iniciada lanza, y la pantalla de la ficha lo muestra como «No pudimos '
        'abrir»', (tester) async {
      final salida = await _montar(tester, _repoConMaria(), sinSesion: true);

      expect(salida.error, isA<StateError>());
      expect(find.text('Editar persona'), findsNothing);
    });
  });

  group('«Dar de baja y crear nueva» (R6)', () {
    testWidgets(
      'dado «Roberto Suárez», cuando elige «Dar de baja y crear nueva», el alta abre en el '
      'mismo espacio con el nombre, el apellido y el teléfono ya escritos y no se escribió nada',
      (tester) async {
        final repo = _repoConMaria();
        await _montar(tester, repo);

        await _hastaElAlta(tester);

        expect(find.text('Nueva persona'), findsOneWidget);
        expect(tester.widget<TextField>(_campo(_nombre)).controller!.text, 'Roberto');
        expect(tester.widget<TextField>(_campo(_apellido)).controller!.text, 'Suárez');
        expect(tester.widget<TextField>(_campo(_telefono)).controller!.text, '091 222 333');
        expect(repo.editadas, isEmpty);
        expect(repo.recibidas, isEmpty);
        expect(repo.bajasRecibidas, isEmpty);
      },
    );

    testWidgets('dado el alta con lo escrito, cuando se guarda, la nueva queda registrada ANTES de '
        'abrir la baja de la original, y al confirmarla avisa «Guardamos a Roberto»', (
      tester,
    ) async {
      final repo = _repoConMaria();
      final salida = await _montar(tester, repo);
      await _hastaElAlta(tester);

      await _tocarBoton(tester, _guardarPersona);

      // La nueva ya está guardada y la hoja de baja de María está delante: todavía no se dio de baja.
      expect(repo.recibidas.single.persona.nombre, 'Roberto');
      expect(repo.recibidas.single.persona.apellido, 'Suárez');
      expect(repo.recibidas.single.persona.telefono, '091 222 333');
      expect(repo.recibidas.single.vinculo.espacioId, 'esp-1');
      expect(find.text('¿Dar de baja a María?'), findsOneWidget);
      expect(repo.bajasRecibidas, isEmpty);

      await _tocarBoton(tester, 'Dar de baja');

      expect(repo.bajasRecibidas.single.personaId, 'per-1');
      expect(find.text(_guardadaRoberto), findsOneWidget);
      expect(find.text(_sinLaBaja), findsNothing);
      expect(salida.terminadas, 1);
    });

    testWidgets('dada una original con saldo, cuando se guarda la nueva, la baja pide sus dos '
        'confirmaciones y recién después se da de baja', (tester) async {
      final repo = _repoConMaria();
      await _montar(tester, repo, cuentas: CuentasFalsas(cuenta: cuentaConSaldo));
      await _hastaElAlta(tester);
      await _tocarBoton(tester, _guardarPersona);

      expect(find.textContaining('te debe'), findsOneWidget);
      await _tocarBoton(tester, 'Dar de baja igual');
      expect(repo.bajasRecibidas, isEmpty);
      await _tocarBoton(tester, 'Sí, dar de baja');

      expect(repo.bajasRecibidas.single.personaId, 'per-1');
      expect(repo.recibidas, hasLength(1));
      expect(find.text(_guardadaRoberto), findsOneWidget);
    });

    testWidgets(
      'dado que cancela el alta («Cerrar» y «Descartar»), cuando vuelve, no cambia nada: ni '
      'la nueva ni la baja, y la original sigue editable',
      (tester) async {
        final repo = _repoConMaria();
        final salida = await _montar(tester, repo);
        await _hastaElAlta(tester);

        await tester.tap(find.byTooltip('Cerrar'));
        await asentar(tester);
        await tester.tap(find.text('Descartar'));
        await asentar(tester);

        expect(repo.recibidas, isEmpty);
        expect(repo.bajasRecibidas, isEmpty);
        expect(repo.editadas, isEmpty);
        expect(find.text('¿Dar de baja a María?'), findsNothing);
        expect(find.text(_guardadaRoberto), findsNothing);
        expect(find.text(_sinLaBaja), findsNothing);
        expect(salida.terminadas, 1);
      },
    );

    testWidgets(
      'dado que cancela el alta y vuelve a entrar, cuando repite el camino hasta el final, '
      'la nueva y la baja se hacen una sola vez',
      (tester) async {
        final repo = _repoConMaria();
        final salida = await _montar(tester, repo);
        await _hastaElAlta(tester);
        await tester.tap(find.byTooltip('Cerrar'));
        await asentar(tester);
        await tester.tap(find.text('Descartar'));
        await asentar(tester);
        expect(salida.terminadas, 1);

        await tester.tap(find.text('editar'));
        await asentar(tester);
        // La edición abre con María otra vez: nada se escribió.
        expect(tester.widget<TextField>(_campo(_nombre)).controller!.text, 'María');
        await _hastaElAlta(tester);
        await _tocarBoton(tester, _guardarPersona);
        await _tocarBoton(tester, 'Dar de baja');

        expect(repo.recibidas, hasLength(1));
        expect(repo.bajasRecibidas, hasLength(1));
        expect(salida.terminadas, 2);
      },
    );

    testWidgets(
      'dado que la hoja de baja se cancela, cuando vuelve, la nueva queda registrada y el '
      'aviso dice que la original sigue y dónde darla de baja',
      (tester) async {
        final repo = _repoConMaria();
        final salida = await _montar(tester, repo);
        await _hastaElAlta(tester);
        await _tocarBoton(tester, _guardarPersona);

        await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
        await asentar(tester);

        expect(repo.recibidas, hasLength(1));
        expect(repo.bajasRecibidas, isEmpty);
        expect(find.text(_sinLaBaja), findsOneWidget);
        expect(find.text(_guardadaRoberto), findsNothing);
        expect(salida.terminadas, 1);
      },
    );

    testWidgets(
      'dado que la baja falla, cuando se cierra la hoja, la nueva queda registrada, el botón '
      'de la hoja volvió a quedar habilitado y el aviso dice que la original sigue',
      (tester) async {
        final repo = _repoConMaria()..resultadosBaja.add(const FailureInesperado());
        await _montar(tester, repo);
        await _hastaElAlta(tester);
        await _tocarBoton(tester, _guardarPersona);

        await _tocarBoton(tester, 'Dar de baja');
        expect(find.text('No pudimos dar de baja a María. Probá de nuevo.'), findsOneWidget);
        final boton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Dar de baja'));
        expect(boton.onPressed, isNotNull, reason: 'ningún «Dando de baja…» queda trabado');

        await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
        await asentar(tester);

        expect(repo.recibidas, hasLength(1));
        expect(find.text(_sinLaBaja), findsOneWidget);
      },
    );

    testWidgets(
      'dado que la baja falla una vez, cuando reintenta en la misma hoja, se da de baja y '
      'avisa «Guardamos a Roberto»',
      (tester) async {
        final repo = _repoConMaria()..resultadosBaja.add(const FailureInesperado());
        await _montar(tester, repo);
        await _hastaElAlta(tester);
        await _tocarBoton(tester, _guardarPersona);

        await _tocarBoton(tester, 'Dar de baja');
        await _tocarBoton(tester, 'Dar de baja');

        expect(repo.bajasRecibidas, hasLength(2));
        expect(repo.recibidas, hasLength(1));
        expect(find.text(_guardadaRoberto), findsOneWidget);
      },
    );

    testWidgets('dado que guardar la nueva falla, cuando reintenta, la original no se da de baja '
        'mientras la nueva no esté guardada, y con el reintento sigue el camino', (tester) async {
      final repo = _repoConMaria()..resultados.add(const FailureInesperado());
      await _montar(tester, repo);
      await _hastaElAlta(tester);

      await _tocarBoton(tester, _guardarPersona);
      // Falló: sigue el alta con lo escrito, sin hoja de baja ni baja escrita.
      expect(find.text('No pudimos guardar a la persona. Probá de nuevo.'), findsOneWidget);
      expect(find.text('¿Dar de baja a María?'), findsNothing);
      expect(repo.bajasRecibidas, isEmpty);
      expect(tester.widget<TextField>(_campo(_nombre)).controller!.text, 'Roberto');

      await _tocarBoton(tester, 'Reintentar');
      expect(find.text('¿Dar de baja a María?'), findsOneWidget);
      await _tocarBoton(tester, 'Dar de baja');

      expect(repo.bajasRecibidas.single.personaId, 'per-1');
      expect(find.text(_guardadaRoberto), findsOneWidget);
    });

    testWidgets(
      'dado un doble toque en «Guardar persona», cuando termina, hay una sola persona nueva '
      'y una sola hoja de baja',
      (tester) async {
        final repo = _repoConMaria()..compuerta = Completer<void>();
        await _montar(tester, repo);
        await _hastaElAlta(tester);

        await tester.tap(find.widgetWithText(FilledButton, _guardarPersona));
        await tester.pump();
        // Mientras guarda, el botón dice «Guardando…» y no atiende otro toque.
        await tester.tap(find.widgetWithText(FilledButton, 'Guardando…'), warnIfMissed: false);
        await tester.pump();
        repo.compuerta!.complete();
        await asentar(tester);

        expect(repo.recibidas, hasLength(1));
        expect(find.text('¿Dar de baja a María?'), findsOneWidget);
        expect(repo.bajasRecibidas, isEmpty);
      },
    );

    testWidgets('dado un doble toque en «Dar de baja», cuando termina, se escribe una sola baja', (
      tester,
    ) async {
      final repo = _repoConMaria()..compuertaBaja = Completer<void>();
      await _montar(tester, repo);
      await _hastaElAlta(tester);
      await _tocarBoton(tester, _guardarPersona);

      await tester.tap(find.widgetWithText(FilledButton, 'Dar de baja'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Dando de baja…'), warnIfMissed: false);
      await tester.pump();
      repo.compuertaBaja!.complete();
      await asentar(tester);

      expect(repo.bajasRecibidas, hasLength(1));
      expect(find.text(_guardadaRoberto), findsOneWidget);
    });

    testWidgets(
      'dada una persona con nombres largos y la letra al 200 % en 320×568, cuando hace el '
      'camino completo, ninguna pantalla desborda y el aviso final se ve',
      (tester) async {
        final repo = PersonaRepositorioFalso()
          ..sembrar([clienteDePersonas('per-1', 'María', apellido: 'Fernández')]);
        await _montar(tester, repo, escala: 2, tamano: const Size(320, 568));
        final largo = 'Constantino' * 5;
        await _escribir(tester, _nombre, largo);
        await _escribir(tester, _apellido, 'Villalobos' * 5);
        await _tocarTexto(tester, _bajaYNueva);
        expect(find.text('Nueva persona'), findsOneWidget);

        await _tocarBoton(tester, _guardarPersona);
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Dar de baja'));
        await _tocarBoton(tester, 'Dar de baja');

        expect(tester.takeException(), isNull);
        expect(repo.recibidas.single.persona.nombre, largo);
        expect(repo.bajasRecibidas, hasLength(1));
      },
    );
  });
}

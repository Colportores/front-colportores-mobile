// HU-UBI-011 / vista 32D, artboards 01 a 03: la hoja «¿Dar de baja a …?» sin saldo, con saldo (resumen)
// y la segunda confirmación, más los estados que el canvas no dibuja (revisando, error al revisar, falla
// al escribir, en curso) y sus casos límite (doble toque, falla a mitad, deuda que llega, volver a abrir,
// textos largos y textScaler 2.0).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_baja_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'baja_persona_arnes.dart';
import 'personas_arnes.dart';

final _darDeBaja = find.widgetWithText(FilledButton, 'Dar de baja');
final _darDeBajaIgual = find.widgetWithText(FilledButton, 'Dar de baja igual');
final _siDarDeBaja = find.widgetWithText(FilledButton, 'Sí, dar de baja');
final _cancelar = find.widgetWithText(TextButton, 'Cancelar');
final _noVolver = find.widgetWithText(TextButton, 'No, volver');

PersonaRepositorioFalso _repoConJorge() =>
    PersonaRepositorioFalso()..sembrar([clienteDePersonas('p1', 'Jorge', apellido: 'Fernández')]);

void main() {
  group('32D·01 · dar de baja sin saldo', () {
    testWidgets(
      'dada una persona sin ventas, cuando se abre, muestra el título, el texto del canvas '
      'y las dos acciones',
      (tester) async {
        await montarHojaBaja(tester);

        expect(find.text('¿Dar de baja a Jorge?'), findsOneWidget);
        expect(
          find.text(
            'Deja de aparecer en el depto. No se borra: queda en «Ver bajas» y se puede reactivar.',
          ),
          findsOneWidget,
        );
        expect(_darDeBaja, findsOneWidget);
        expect(_cancelar, findsOneWidget);
        expect(find.textContaining('te debe'), findsNothing);
      },
    );

    testWidgets('cuando confirma, da de baja una vez con el reloj, cierra la hoja y devuelve la '
        'persona dada de baja', (tester) async {
      final repo = _repoConJorge();
      final resultado = await montarHojaBaja(tester, repo: repo);

      await tester.tap(_darDeBaja);
      await asentar(tester);

      expect(repo.bajasRecibidas, hasLength(1));
      expect(repo.bajasRecibidas.single.personaId, 'p1');
      expect(repo.bajasRecibidas.single.ahora, ahoraBaja);
      expect(repo.bajasRecibidas.single.motivo, isNull);
      expect(resultado.cierres, 1);
      final salida = resultado.salida! as PersonaBajaRealizada;
      expect(salida.persona.auditoria.deletedAt, ahoraBaja);
      expect(find.text('¿Dar de baja a Jorge?'), findsNothing);
    });

    testWidgets('cuando toca «Cancelar», cierra sin escribir nada', (tester) async {
      final repo = _repoConJorge();
      final resultado = await montarHojaBaja(tester, repo: repo);

      await tester.tap(_cancelar);
      await asentar(tester);

      expect(repo.bajasRecibidas, isEmpty);
      expect(resultado.cierres, 1);
      expect(resultado.salida, isNull);
    });

    testWidgets('dada una persona con saldo en cero, no pide la doble confirmación', (
      tester,
    ) async {
      final repo = _repoConJorge();
      await montarHojaBaja(
        tester,
        repo: repo,
        cuentas: CuentasFalsas(
          cuenta: const ResumenCuentaPersona(
            compradoCentavos: 1000,
            pagadoCentavos: 1000,
            saldoCentavos: 0,
            entregasHechas: 1,
            entregasTotales: 1,
          ),
        ),
      );

      expect(_darDeBaja, findsOneWidget);
      expect(_darDeBajaIgual, findsNothing);
    });
  });

  group('32D·02 · con saldo: resumen', () {
    testWidgets('dada una persona que debe, cuando se abre, muestra el aviso con la deuda y la '
        'entrega pendiente y los cuatro renglones de la cuenta', (tester) async {
      await montarHojaBaja(
        tester,
        persona: personaParaBaja(nombre: 'María'),
        cuentas: CuentasFalsas(cuenta: cuentaConSaldo),
      );

      expect(find.text('¿Dar de baja a María?'), findsOneWidget);
      expect(find.text('María te debe \$ 1.200 y tiene 1 entrega pendiente.'), findsOneWidget);
      for (final texto in [
        'Comprado',
        '\$ 4.500',
        'Entregado',
        '1 de 2',
        'Pagado',
        '\$ 3.300',
        'Saldo',
        '\$ 1.200',
      ]) {
        expect(find.text(texto), findsOneWidget, reason: texto);
      }
      expect(_darDeBajaIgual, findsOneWidget);
      expect(_cancelar, findsOneWidget);
      expect(_darDeBaja, findsNothing);
    });

    testWidgets('«Dar de baja igual» no escribe: lleva a la segunda confirmación', (tester) async {
      final repo = _repoConJorge();
      await montarHojaBaja(
        tester,
        repo: repo,
        cuentas: CuentasFalsas(cuenta: cuentaConSaldo),
      );

      await tester.tap(_darDeBajaIgual);
      await asentar(tester);

      expect(repo.bajasRecibidas, isEmpty);
      expect(find.text('¿Seguro?'), findsOneWidget);
    });

    testWidgets('«Cancelar» en el resumen cierra sin escribir', (tester) async {
      final repo = _repoConJorge();
      final resultado = await montarHojaBaja(
        tester,
        repo: repo,
        cuentas: CuentasFalsas(cuenta: cuentaConSaldo),
      );

      await tester.tap(_cancelar);
      await asentar(tester);

      expect(repo.bajasRecibidas, isEmpty);
      expect(resultado.salida, isNull);
      expect(resultado.cierres, 1);
    });

    testWidgets('sin entregas pendientes el aviso dice solo la deuda', (tester) async {
      await montarHojaBaja(
        tester,
        persona: personaParaBaja(nombre: 'María'),
        cuentas: CuentasFalsas(
          cuenta: const ResumenCuentaPersona(
            compradoCentavos: 450000,
            pagadoCentavos: 330000,
            saldoCentavos: 120000,
            entregasHechas: 2,
            entregasTotales: 2,
          ),
        ),
      );

      expect(find.text('María te debe \$ 1.200.'), findsOneWidget);
    });
  });

  group('32D·03 · con saldo: segunda confirmación', () {
    Future<PersonaRepositorioFalso> aLaSegunda(WidgetTester tester) async {
      final repo = _repoConJorge();
      await montarHojaBaja(
        tester,
        repo: repo,
        persona: personaParaBaja(nombre: 'María'),
        cuentas: CuentasFalsas(cuenta: cuentaConSaldo),
      );
      await tester.tap(_darDeBajaIgual);
      await asentar(tester);
      return repo;
    }

    testWidgets('muestra «¿Seguro?», que la deuda sigue en la cuenta, y las dos acciones', (
      tester,
    ) async {
      await aLaSegunda(tester);

      expect(find.text('¿Seguro?'), findsOneWidget);
      expect(
        find.text('La deuda de \$ 1.200 sigue en tu cuenta aunque María esté de baja.'),
        findsOneWidget,
      );
      expect(_siDarDeBaja, findsOneWidget);
      expect(_noVolver, findsOneWidget);
    });

    testWidgets('«No, volver» vuelve al resumen sin escribir y se puede avanzar otra vez', (
      tester,
    ) async {
      final repo = await aLaSegunda(tester);

      await tester.tap(_noVolver);
      await asentar(tester);
      expect(find.text('¿Dar de baja a María?'), findsOneWidget);
      expect(repo.bajasRecibidas, isEmpty);

      await tester.tap(_darDeBajaIgual);
      await asentar(tester);
      expect(find.text('¿Seguro?'), findsOneWidget);
    });

    testWidgets('«Sí, dar de baja» escribe una vez y devuelve la persona; sin volver a mirar la '
        'deuda', (tester) async {
      final repo = _repoConJorge();
      final cuentas = CuentasFalsas(cuenta: cuentaConSaldo);
      final resultado = await montarHojaBaja(tester, repo: repo, cuentas: cuentas);
      await tester.tap(_darDeBajaIgual);
      await asentar(tester);
      final antes = cuentas.consultas;

      await tester.tap(_siDarDeBaja);
      await asentar(tester);

      expect(repo.bajasRecibidas, hasLength(1));
      expect(cuentas.consultas, antes);
      expect(resultado.salida, isA<PersonaBajaRealizada>());
    });

    testWidgets('«Cancelar» no está en la segunda confirmación: la salida es «No, volver», y el '
        'atrás del sistema cierra sin escribir', (tester) async {
      final repo = _repoConJorge();
      final resultado = await montarHojaBaja(
        tester,
        repo: repo,
        cuentas: CuentasFalsas(cuenta: cuentaConSaldo),
      );
      await tester.tap(_darDeBajaIgual);
      await asentar(tester);

      expect(_cancelar, findsNothing);
      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(repo.bajasRecibidas, isEmpty);
      expect(resultado.cierres, 1);
      expect(resultado.salida, isNull);
    });
  });

  group('estados que el canvas no dibuja', () {
    testWidgets('mientras revisa la cuenta, lo dice y solo se puede cancelar', (tester) async {
      final cuentas = CuentasFalsas(compuerta: Completer<void>());
      await montarHojaBaja(tester, cuentas: cuentas);

      expect(find.text('Revisando la cuenta de Jorge…'), findsOneWidget);
      expect(_darDeBaja, findsNothing);
      expect(_cancelar, findsOneWidget);

      cuentas.compuerta!.complete();
      await asentar(tester);

      expect(find.text('Revisando la cuenta de Jorge…'), findsNothing);
      expect(_darDeBaja, findsOneWidget);
    });

    testWidgets('si no se puede leer la cuenta, no ofrece la baja: avisa y deja «Reintentar»', (
      tester,
    ) async {
      final repo = _repoConJorge();
      final cuentas = CuentasFalsas(lanza: StateError('no se pudo leer'));
      await montarHojaBaja(tester, repo: repo, cuentas: cuentas);

      expect(find.text('No pudimos revisar si Jorge tiene saldo. Probá de nuevo.'), findsOneWidget);
      expect(_darDeBaja, findsNothing);
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
      expect(repo.bajasRecibidas, isEmpty);

      cuentas.lanza = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await asentar(tester);

      expect(find.textContaining('No pudimos revisar'), findsNothing);
      expect(_darDeBaja, findsOneWidget);
    });

    testWidgets('si falla al escribir, avisa qué pasó, el botón vuelve a estar habilitado y el '
        'reintento funciona', (tester) async {
      final repo = _repoConJorge()..resultadosBaja.add(const FailureInesperado());
      final resultado = await montarHojaBaja(tester, repo: repo);

      await tester.tap(_darDeBaja);
      await asentar(tester);

      expect(find.text('No pudimos dar de baja a Jorge. Probá de nuevo.'), findsOneWidget);
      expect(resultado.cierres, 0);
      final boton = tester.widget<FilledButton>(_darDeBaja);
      expect(boton.onPressed, isNotNull);
      expect(find.text('Dando de baja…'), findsNothing);

      await tester.tap(_darDeBaja);
      await asentar(tester);

      expect(repo.bajasRecibidas, hasLength(2));
      expect(resultado.salida, isA<PersonaBajaRealizada>());
    });

    testWidgets('si el repositorio dice qué pasó (el espacio está de baja), muestra ese mensaje', (
      tester,
    ) async {
      final repo = _repoConJorge()
        ..resultadosBaja.add(
          const FailureValidacion(
            campos: {'persona': 'Su espacio está dado de baja: solo lectura.'},
          ),
        );
      await montarHojaBaja(tester, repo: repo);

      await tester.tap(_darDeBaja);
      await asentar(tester);

      expect(find.text('Su espacio está dado de baja: solo lectura.'), findsOneWidget);
    });

    testWidgets('mientras escribe, dice «Dando de baja…», no se puede tocar ni cerrar, y al '
        'terminar cierra', (tester) async {
      final repo = _repoConJorge()..compuertaBaja = Completer<void>();
      final resultado = await montarHojaBaja(tester, repo: repo);

      await tester.tap(_darDeBaja);
      await tester.pump();

      expect(find.text('Dando de baja…'), findsOneWidget);
      expect(tester.widget<TextButton>(_cancelar).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await asentar(tester);
      expect(resultado.cierres, 0);
      expect(find.text('¿Dar de baja a Jorge?'), findsOneWidget);

      repo.compuertaBaja!.complete();
      await asentar(tester);

      expect(resultado.salida, isA<PersonaBajaRealizada>());
    });
  });

  group('casos límite', () {
    testWidgets('dos toques seguidos en «Dar de baja» piden la baja una sola vez', (tester) async {
      final repo = _repoConJorge()..compuertaBaja = Completer<void>();
      await montarHojaBaja(tester, repo: repo);

      await tester.tap(_darDeBaja);
      await tester.tap(_darDeBaja, warnIfMissed: false);
      repo.compuertaBaja!.complete();
      await asentar(tester);

      expect(repo.bajasRecibidas, hasLength(1));
    });

    testWidgets('dos toques seguidos en «Sí, dar de baja» piden la baja una sola vez', (
      tester,
    ) async {
      final repo = _repoConJorge()..compuertaBaja = Completer<void>();
      await montarHojaBaja(
        tester,
        repo: repo,
        cuentas: CuentasFalsas(cuenta: cuentaConSaldo),
      );
      await tester.tap(_darDeBajaIgual);
      await asentar(tester);

      await tester.tap(_siDarDeBaja);
      await tester.tap(_siDarDeBaja, warnIfMissed: false);
      repo.compuertaBaja!.complete();
      await asentar(tester);

      expect(repo.bajasRecibidas, hasLength(1));
    });

    testWidgets('si la deuda llega entre que se abre la hoja y se confirma, no escribe: muestra el '
        'resumen', (tester) async {
      final repo = _repoConJorge();
      await montarHojaBaja(
        tester,
        repo: repo,
        persona: personaParaBaja(nombre: 'María'),
        cuentas: CuentasFalsas(secuencia: [null, cuentaConSaldo]),
      );
      expect(_darDeBaja, findsOneWidget);

      await tester.tap(_darDeBaja);
      await asentar(tester);

      expect(repo.bajasRecibidas, isEmpty);
      expect(find.text('María te debe \$ 1.200 y tiene 1 entrega pendiente.'), findsOneWidget);
      expect(_darDeBajaIgual, findsOneWidget);
    });

    testWidgets('volver atrás y reentrar: cada apertura empieza de cero y no queda nada escrito', (
      tester,
    ) async {
      final repo = _repoConJorge();
      final cuentas = CuentasFalsas(cuenta: cuentaConSaldo);
      final resultado = await montarHojaBaja(tester, repo: repo, cuentas: cuentas);
      await tester.tap(_darDeBajaIgual);
      await asentar(tester);
      await tester.binding.handlePopRoute();
      await asentar(tester);

      await tester.tap(find.text('abrir baja'));
      await asentar(tester);

      expect(find.text('¿Dar de baja a Jorge?'), findsOneWidget);
      expect(_darDeBajaIgual, findsOneWidget);
      expect(find.text('¿Seguro?'), findsNothing);
      expect(repo.bajasRecibidas, isEmpty);
      expect(resultado.cierres, 1);
    });

    testWidgets('si la persona ya estaba de baja (otro dispositivo, doble toque anterior), el '
        'repositorio la devuelve igual y la hoja cierra', (tester) async {
      final repo = PersonaRepositorioFalso()..sembrar([clienteDeBajaDePersonas('p1', 'Jorge')]);
      final resultado = await montarHojaBaja(tester, repo: repo);

      await tester.tap(_darDeBaja);
      await asentar(tester);

      expect(resultado.salida, isA<PersonaBajaRealizada>());
    });

    for (final fase in ['sin saldo', 'resumen', 'confirmación']) {
      testWidgets('con un nombre larguísimo y textScaler 2.0 a 320×568 ($fase) no desborda y las '
          'acciones se alcanzan', (tester) async {
        final persona = personaParaBaja(
          nombre: 'Maximiliano Alejandro Bartolomé',
          apellido: 'Fernández de la Vega y Altamirano',
        );
        await montarHojaBaja(
          tester,
          persona: persona,
          cuentas: CuentasFalsas(cuenta: fase == 'sin saldo' ? null : cuentaConSaldo),
          escala: 2,
          tamano: const Size(320, 568),
        );
        if (fase == 'confirmación') {
          await tester.tap(_darDeBajaIgual);
          await asentar(tester);
        }

        expect(tester.takeException(), isNull);
        final principal = switch (fase) {
          'sin saldo' => _darDeBaja,
          'resumen' => _darDeBajaIgual,
          _ => _siDarDeBaja,
        };
        expect(principal, findsOneWidget);
        final rect = tester.getRect(principal);
        expect(rect.bottom, lessThanOrEqualTo(568));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.height, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('el título es un encabezado y los botones miden al menos 48 dp', (tester) async {
      final handle = tester.ensureSemantics();
      await montarHojaBaja(tester, cuentas: CuentasFalsas(cuenta: cuentaConSaldo));

      expect(tester.getSemantics(find.text('¿Dar de baja a Jorge?')), isSemantics(isHeader: true));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });
}

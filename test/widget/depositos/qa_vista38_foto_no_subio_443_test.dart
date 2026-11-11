// QA de 38A-08 «No pudimos enviar el ticket» y del chip de ACCIONES apagado con $ 0 en mano (#443,
// PR #683): el aviso en «Registrar depósito» y en Mi Cuenta en los dos teléfonos de la matriz
// (360×640 y 412×915, texto 1,0× y 2,0×), guías de toque, casos límite del reintento y del chip.
// Los hallazgos llevan `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
// Capturas solo con `--dart-define=QA_CAPTURAS=true` (a `.dart_tool/qa_capturas/`, nunca al repo).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/cuenta_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/cuenta/presentation/textos_cuenta.dart';
import 'package:colportores_mobile/features/depositos/presentation/pages/registrar_deposito_page.dart';
import 'package:colportores_mobile/features/depositos/presentation/providers/depositos_providers.dart';
import 'package:colportores_mobile/features/depositos/presentation/textos_deposito.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/qa_vista33_deposito_443_arnes.dart';

const _aviso = Key('deposito_ticket_sin_subir');
const _chip = Key('cuenta_registrar_deposito');

/// Los tickets sin subir que ve la pantalla y qué pasa al tocar «Reintentar ahora».
final class _Cola {
  _Cola([this.inicial = 1]);

  final int inicial;
  var reintentos = 0;
  Future<void> Function() alReintentar = () async {};
  late final StreamController<int> _cuantos = StreamController<int>.broadcast();
  var _ultimo = 0;

  /// Como Drift: quien se suscribe recibe enseguida el último valor.
  Stream<int> _stream() async* {
    yield _ultimo;
    yield* _cuantos.stream;
  }

  List<Override> get overrides {
    _ultimo = inicial;
    return [
      ticketsDeDepositoSinSubirProvider.overrideWith((ref) => _stream()),
      reintentarSubidaDeTicketsProvider.overrideWithValue(() {
        reintentos++;
        return alReintentar();
      }),
    ];
  }

  Future<void> emitir(WidgetTester tester, int n) async {
    _ultimo = n;
    _cuantos.add(n);
    await tester.pump();
    await tester.pump();
  }
}

Finder _reintentar() => find.descendant(of: find.byKey(_aviso), matching: find.byType(TextButton));

/// «Registrar depósito» con [cola], a [tamano] y [escala], con fuentes reales.
Future<ArnesDeDeposito> _montarDeposito(
  WidgetTester tester,
  _Cola cola, {
  Size tamano = t360x640,
  double escala = 1,
  ArnesDeDeposito? arnes,
  bool abrir = true,
}) async {
  final a = arnes ?? ArnesDeDeposito();
  await cargarFuentes443(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...overrides443(a), ...cola.overrides],
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
                key: const Key('abrir_deposito'),
                onPressed: () =>
                    unawaited(RegistrarDepositoPage.abrir(context, colportorId: 'col-1')),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirDeposito(tester);
  return a;
}

/// «Mi Cuenta» con [cola] y el resumen dado, con fuentes reales.
Future<void> _montarCuenta(
  WidgetTester tester,
  _Cola cola,
  RepositorioDeCuentaControlable repo, {
  Size tamano = t360x640,
  double escala = 1,
  TipoConexion conexion = TipoConexion.wifi,
}) async {
  await cargarFuentes443(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final arnes = ArnesDeDeposito(conexion: conexion, extras: cola.overrides);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        resumenDeCuentaRepositoryProvider.overrideWithValue(repo),
        ...arnes.overridesSinCuenta,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const Scaffold(body: CuentaPage(colportorId: 'col-1', activa: true)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // -------- Matriz: 4 tamaños × estados de «Registrar depósito» y de Mi Cuenta ----------------------
  for (final tamano in tamanos443) {
    for (final escala in escalas443) {
      final suf = sufijo443(tamano, escala);

      group('matriz $suf', () {
        testWidgets('Registrar depósito · un ticket sin subir', (tester) async {
          final semantica = tester.ensureSemantics();
          await _montarDeposito(tester, _Cola(), tamano: tamano, escala: escala);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(_aviso), findsOneWidget);
          expect(
            find.text(
              'No pudimos enviar el ticket. Quedó guardado en el teléfono y lo reintentamos solo.',
            ),
            findsOneWidget,
          );
          expect(find.text('Reintentar ahora'), findsOneWidget);
          await capturar443(tester, '38a08_registrar_uno_$suf');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        });

        testWidgets('Registrar depósito · tres tickets (plural)', (tester) async {
          await _montarDeposito(tester, _Cola(3), tamano: tamano, escala: escala);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(TextosDeposito.ticketsSinSubir(3)), findsOneWidget);
          await capturar443(tester, '38a08_registrar_tres_$suf');
        });

        testWidgets('Registrar depósito · 1.000 tickets: el número largo no desborda', (
          tester,
        ) async {
          await _montarDeposito(tester, _Cola(1000), tamano: tamano, escala: escala);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('1000 tickets'), findsOneWidget);
        });

        testWidgets('Registrar depósito · aviso + error al registrar (el error va arriba)', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          final arnes = ArnesDeDeposito()
            ..depositos.fallarUnaVezCon = const FailureDepositoNoGuardado();
          await _montarDeposito(tester, _Cola(), tamano: tamano, escala: escala, arnes: arnes);
          await tester.pumpAndSettle();
          await escribirMonto(tester, '1800');
          await sacarLaFoto(tester);
          await tocarRegistrar(tester);
          expect(tester.takeException(), isNull);
          // El error de la acción es lo primero que se ve y el aviso de la foto sigue a mano.
          expect(find.byKey(const Key('deposito_error')), findsOneWidget);
          expect(find.byKey(_aviso), findsOneWidget);
          final lista = tester.getRect(find.byKey(const Key('deposito_lista')));
          final error = tester.getRect(find.byKey(const Key('deposito_error')));
          expect(error.top, greaterThanOrEqualTo(lista.top));
          expect(error.bottom, lessThanOrEqualTo(lista.bottom));
          expect(
            tester.getTopLeft(find.byKey(const Key('deposito_error'))).dy,
            lessThan(tester.getTopLeft(find.byKey(_aviso)).dy),
          );
          await capturar443(tester, '38a08_registrar_error_mas_aviso_$suf');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        });

        testWidgets('Registrar depósito · aviso + sin conexión', (tester) async {
          final arnes = ArnesDeDeposito(conexion: TipoConexion.sinConexion);
          await _montarDeposito(tester, _Cola(2), tamano: tamano, escala: escala, arnes: arnes);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('deposito_sin_conexion')), findsOneWidget);
          expect(find.byKey(_aviso), findsOneWidget);
          await capturar443(tester, '38a08_registrar_sin_conexion_$suf');
        });

        testWidgets('Mi Cuenta · aviso arriba de las tarjetas', (tester) async {
          final semantica = tester.ensureSemantics();
          await _montarCuenta(
            tester,
            _Cola(),
            RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
            tamano: tamano,
            escala: escala,
          );
          expect(tester.takeException(), isNull);
          expect(find.byKey(_aviso), findsOneWidget);
          await capturar443(tester, '38a08_cuenta_aviso_$suf');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        });

        testWidgets('Mi Cuenta · cuenta nueva: chip apagado con su motivo', (tester) async {
          final semantica = tester.ensureSemantics();
          await _montarCuenta(
            tester,
            _Cola(0),
            RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
            tamano: tamano,
            escala: escala,
          );
          await tester.ensureVisible(find.byKey(_chip));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(tester.widget<OutlinedButton>(find.byKey(_chip)).onPressed, isNull);
          expect(find.text(TextosCuenta.sinPlataParaDepositar), findsOneWidget);
          await capturar443(tester, '38a08_cuenta_chip_apagado_$suf');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        });

        testWidgets('Mi Cuenta · cuenta nueva + aviso de foto + sin conexión', (tester) async {
          await _montarCuenta(
            tester,
            _Cola(2),
            RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
            tamano: tamano,
            escala: escala,
            conexion: TipoConexion.sinConexion,
          );
          await tester.ensureVisible(find.byKey(_chip));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byKey(_aviso), findsOneWidget);
          await capturar443(tester, '38a08_cuenta_nueva_aviso_sin_conexion_$suf');
        });
      });
    }
  }

  // -------- Casos límite del reintento ----------------------------------------------------------------
  group('casos límite del reintento', () {
    testWidgets('el aviso aparece mientras la persona tipea: lo tipeado y el foco no se pierden', (
      tester,
    ) async {
      final cola = _Cola(0);
      await _montarDeposito(tester, cola);
      await tester.pumpAndSettle();
      await escribirMonto(tester, '1800');
      expect(find.byKey(_aviso), findsNothing);

      await cola.emitir(tester, 1);
      await tester.pumpAndSettle();
      expect(find.byKey(_aviso), findsOneWidget);
      final campo = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('deposito_monto')),
          matching: find.byType(TextField),
        ),
      );
      expect(campo.controller!.text, '1800');
      expect(campo.focusNode?.hasFocus ?? FocusManager.instance.primaryFocus != null, isTrue);
    });

    testWidgets(
      'con el teclado abierto a 360×640 y 200 %, el monto sigue a la vista con el aviso',
      (tester) async {
        final cola = _Cola(3);
        await _montarDeposito(tester, cola, escala: 2);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await escribirMonto(tester, '1800');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final monto = tester.getRect(
          find.descendant(
            of: find.byKey(const Key('deposito_monto')),
            matching: find.byType(TextField),
          ),
        );
        expect(monto.bottom, lessThanOrEqualTo(640 - 280), reason: 'el campo queda tapado');
        expect(monto.top, greaterThanOrEqualTo(0));
      },
    );

    testWidgets('0 → 1 → 0 → 1: el botón sigue respondiendo después de que el aviso se va', (
      tester,
    ) async {
      final cola = _Cola(1);
      cola.alReintentar = () async => cola._cuantos.add(0);
      await _montarDeposito(tester, cola);
      await tester.pumpAndSettle();
      await tester.tap(_reintentar());
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_aviso), findsNothing);

      await cola.emitir(tester, 1);
      expect(find.byKey(_aviso), findsOneWidget);
      expect(tester.widget<TextButton>(_reintentar()).onPressed, isNotNull);
      await tester.tap(_reintentar());
      await tester.pump();
      expect(cola.reintentos, 2);
    });

    testWidgets('el contador cambia mientras el reintento corre: texto nuevo, botón apagado', (
      tester,
    ) async {
      final cola = _Cola(1);
      final tarda = Completer<void>();
      cola.alReintentar = () => tarda.future;
      await _montarDeposito(tester, cola);
      await tester.pumpAndSettle();
      await tester.tap(_reintentar());
      await tester.pump();
      await cola.emitir(tester, 2);
      expect(find.text(TextosDeposito.ticketsSinSubir(2)), findsOneWidget);
      expect(tester.widget<TextButton>(_reintentar()).onPressed, isNull);
      tarda.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.widget<TextButton>(_reintentar()).onPressed, isNotNull);
    });

    testWidgets('dos toques en el mismo cuadro (sin pump entre uno y otro) hacen una sola pasada', (
      tester,
    ) async {
      final cola = _Cola(1);
      final tarda = Completer<void>();
      cola.alReintentar = () => tarda.future;
      await _montarDeposito(tester, cola);
      await tester.pumpAndSettle();
      final centro = tester.getCenter(_reintentar());
      final a = await tester.startGesture(centro);
      await a.up();
      final b = await tester.startGesture(centro);
      await b.up();
      await tester.pump();
      expect(cola.reintentos, 1);
      tarda.complete();
      await tester.pump();
    });

    testWidgets('la pasada lanza al instante (no un Future fallido): el botón no se traba', (
      tester,
    ) async {
      final cola = _Cola(1);
      cola.alReintentar = () => throw StateError('revienta antes de devolver el Future');
      await _montarDeposito(tester, cola);
      await tester.pumpAndSettle();
      await tester.tap(_reintentar());
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.widget<TextButton>(_reintentar()).onPressed, isNotNull);
    });

    testWidgets('la persona cierra «Registrar depósito» con el reintento en curso: sin excepción', (
      tester,
    ) async {
      final cola = _Cola(1);
      final tarda = Completer<void>();
      cola.alReintentar = () => tarda.future;
      await _montarDeposito(tester, cola);
      await tester.pumpAndSettle();
      await tester.tap(_reintentar());
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsNothing);
      tarda.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('reentrada: cerrar y volver a abrir deja el aviso de inmediato', (tester) async {
      final cola = _Cola(2);
      await _montarDeposito(tester, cola);
      await tester.pumpAndSettle();
      expect(find.byKey(_aviso), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await abrirDeposito(tester);
      expect(find.text(TextosDeposito.ticketsSinSubir(2)), findsOneWidget);
    });

    testWidgets('el aviso es una región viva con el botón como único toque del aviso', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montarDeposito(tester, _Cola());
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.byKey(_aviso)), isSemantics(isLiveRegion: true));
      expect(
        find.semantics.byLabel('Reintentar ahora'),
        findsOneWidget,
        reason: 'el lector tiene que poder tocar «Reintentar ahora»',
      );
      semantica.dispose();
    });
  });

  // -------- El chip de ACCIONES ------------------------------------------------------------------------
  group('chip «Registrar depósito» de ACCIONES', () {
    testWidgets(
      'en vivo: con \$ 0 apagado, cuando entra plata se prende y al depositar todo se apaga',
      (tester) async {
        final repo = RepositorioDeCuentaControlable(inicial: resumenCuentaNueva);
        await _montarCuenta(tester, _Cola(0), repo);
        await tester.ensureVisible(find.byKey(_chip));
        expect(tester.widget<OutlinedButton>(find.byKey(_chip)).onPressed, isNull);

        repo.emitir(resumenDelCanvas);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(_chip));
        expect(tester.widget<OutlinedButton>(find.byKey(_chip)).onPressed, isNotNull);
        expect(find.text(TextosCuenta.sinPlataParaDepositar), findsNothing);

        repo.emitir(resumenCuentaNueva);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(_chip));
        expect(tester.widget<OutlinedButton>(find.byKey(_chip)).onPressed, isNull);
        expect(find.text(TextosCuenta.sinPlataParaDepositar), findsOneWidget);
      },
    );

    testWidgets('apagado: el lector lo anuncia desactivado y el motivo se lee aparte', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montarCuenta(
        tester,
        _Cola(0),
        RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
      );
      await tester.ensureVisible(find.byKey(_chip));
      await tester.pump();
      expect(
        tester.getSemantics(find.byKey(_chip)),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false, hasTapAction: false),
      );
      expect(find.semantics.byLabel(TextosCuenta.sinPlataParaDepositar), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('tocarlo apagado no abre nada ni suena un error', (tester) async {
      await _montarCuenta(
        tester,
        _Cola(0),
        RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
      );
      await tester.ensureVisible(find.byKey(_chip));
      await tester.tap(find.byKey(_chip), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text(TextosDeposito.titulo), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«En mano» negativo (se depositó de más) también lo deja apagado', (tester) async {
      await _montarCuenta(
        tester,
        _Cola(0),
        RepositorioDeCuentaControlable(
          inicial: ResumenDeCuenta(enMano: cifra(-300), porCobrar: cifra(0)),
        ),
      );
      await tester.ensureVisible(find.byKey(_chip));
      expect(tester.widget<OutlinedButton>(find.byKey(_chip)).onPressed, isNull);
    });
  });
}

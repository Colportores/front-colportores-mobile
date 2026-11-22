// QA del aviso de la foto del ticket del depósito rechazada para siempre (#443, PR #686, decisión P1
// del 10/11 sobre 38A-08): en «Registrar depósito» y en Mi Cuenta, en los dos teléfonos de la matriz
// (360×640 y 412×915, texto 1,0× y 2,0×), con guías de toque, junto al aviso de 38A-08, con la lectura
// que falla, con la base real y con los casos límite de entrar, salir y volver.
// Los hallazgos llevan `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
// Capturas solo con `--dart-define=QA_CAPTURAS=true` (a `.dart_tool/qa_capturas/`, nunca al repo).
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/database/transaccion_local_drift.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/cuenta_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/data/repositories/deposito_repository_impl.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_con_ticket_use_case.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_use_case.dart';
import 'package:colportores_mobile/features/depositos/presentation/pages/registrar_deposito_page.dart';
import 'package:colportores_mobile/features/depositos/presentation/providers/depositos_providers.dart';
import 'package:colportores_mobile/features/depositos/presentation/textos_deposito.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/ticket_local_data_source_drift.dart';
import 'package:colportores_mobile/features/tickets/data/repositories/ticket_repository_impl.dart';
import 'package:colportores_mobile/features/tickets/domain/usecases/registrar_ticket_use_case.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/qa_vista33_deposito_443_arnes.dart';
import '../../helpers/tickets_falsos.dart';

const _rechazo = Key('deposito_ticket_rechazado');
const _sinSubir = Key('deposito_ticket_sin_subir');
const _chip = Key('cuenta_registrar_deposito');

final _dia8 = DateTime.utc(2026, 11, 8, 15);
final _dia9 = DateTime.utc(2026, 11, 9, 15);

String _textoUna(String dia) =>
    'No pudimos enviar la foto del ticket del depósito del $dia y ya no se puede reintentar. '
    'Avisale a tu coordinador para que lo revise.';

String _textoVarias(int n) =>
    'No pudimos enviar las fotos de $n tickets de depósito y ya no se pueden reintentar. '
    'Avisale a tu coordinador para que los revise.';

/// Lo que la cola de fotos le dice a la pantalla: cuántas siguen reintentándose y qué fechas quedaron
/// rechazadas. Como Drift: quien se suscribe recibe enseguida el último valor.
final class _Cola {
  _Cola({this.sinSubir = 0, this.rechazadas = const []});

  final int sinSubir;
  List<DateTime> rechazadas;
  late final _fechas = StreamController<List<DateTime>>.broadcast();

  Stream<List<DateTime>> _stream() async* {
    yield rechazadas;
    yield* _fechas.stream;
  }

  List<Override> get overrides => [
    ticketsDeDepositoSinSubirProvider.overrideWith((ref) => Stream.value(sinSubir)),
    ticketsDeDepositoRechazadosProvider.overrideWith((ref) => _stream()),
    reintentarSubidaDeTicketsProvider.overrideWithValue(() async {}),
  ];

  Future<void> rechazar(WidgetTester tester, List<DateTime> fechas) async {
    rechazadas = fechas;
    _fechas.add(fechas);
    await tester.pump();
    await tester.pump();
  }
}

/// La lectura de las rechazadas que falla (la base ilegible).
List<Override> _lecturaRota({int sinSubir = 0}) => [
  ticketsDeDepositoSinSubirProvider.overrideWith((ref) => Stream.value(sinSubir)),
  ticketsDeDepositoRechazadosProvider.overrideWith(
    (ref) => Stream<List<DateTime>>.error(StateError('base ilegible')),
  ),
  reintentarSubidaDeTicketsProvider.overrideWithValue(() async {}),
];

Finder _botonesDelAviso(Key aviso) =>
    find.descendant(of: find.byKey(aviso), matching: find.byType(TextButton));

Widget _inicio({double escala = 1}) => MaterialApp(
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
          onPressed: () => unawaited(RegistrarDepositoPage.abrir(context, colportorId: 'col-1')),
          child: const Text('Abrir'),
        ),
      ),
    ),
  ),
);

/// «Registrar depósito» con [overrides] de más, a [tamano] y [escala], con fuentes reales.
Future<ArnesDeDeposito> _montarDeposito(
  WidgetTester tester,
  List<Override> overrides, {
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
      overrides: [...overrides443(a), ...overrides],
      child: _inicio(escala: escala),
    ),
  );
  if (abrir) await abrirDeposito(tester);
  return a;
}

/// «Mi Cuenta» con [overrides] de más y el resumen dado, con fuentes reales.
Future<void> _montarCuenta(
  WidgetTester tester,
  List<Override> overrides,
  RepositorioDeCuentaControlable repo, {
  Size tamano = t360x640,
  double escala = 1,
  TipoConexion conexion = TipoConexion.wifi,
}) async {
  await cargarFuentes443(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final arnes = ArnesDeDeposito(conexion: conexion, extras: overrides);
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

/// La lista de «Registrar depósito» se arma de a poco: con el texto grande el segundo aviso todavía no
/// existe hasta que se baja a él.
Future<void> _verAviso(WidgetTester tester, Key aviso) async {
  if (find.byKey(aviso).evaluate().isNotEmpty) return;
  await verEnElFormulario(tester, aviso);
}

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

/// El aviso entero cabe en el ancho de la pantalla y no está cortado.
void _entraEnLaPantalla(WidgetTester tester, Key aviso, Size tamano) {
  final r = tester.getRect(find.byKey(aviso));
  expect(r.left, greaterThanOrEqualTo(0));
  expect(r.right, lessThanOrEqualTo(tamano.width));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // -------- Matriz: 2 teléfonos × 2 escalas × estados de «Registrar depósito» y de Mi Cuenta -------
  for (final tamano in tamanos443) {
    for (final escala in escalas443) {
      final suf = sufijo443(tamano, escala);

      group('matriz $suf', () {
        testWidgets('Registrar depósito · una rechazada', (tester) async {
          final semantica = tester.ensureSemantics();
          await _montarDeposito(
            tester,
            _Cola(rechazadas: [_dia9]).overrides,
            tamano: tamano,
            escala: escala,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(_textoUna('09/11')), findsOneWidget);
          expect(_botonesDelAviso(_rechazo), findsNothing, reason: 'no hay nada que reintentar');
          expect(find.byKey(_sinSubir), findsNothing);
          _entraEnLaPantalla(tester, _rechazo, tamano);
          await capturar443(tester, '38a08_rechazada_registrar_una_$suf');
          await _guias(tester);
          semantica.dispose();
        });

        testWidgets('Registrar depósito · varias rechazadas (plural)', (tester) async {
          await _montarDeposito(
            tester,
            _Cola(rechazadas: [_dia8, _dia9]).overrides,
            tamano: tamano,
            escala: escala,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(_textoVarias(2)), findsOneWidget);
          await capturar443(tester, '38a08_rechazada_registrar_varias_$suf');
        });

        testWidgets('Registrar depósito · 1.000 rechazadas: el número largo no desborda', (
          tester,
        ) async {
          final mil = [for (var i = 0; i < 1000; i++) _dia8.add(Duration(minutes: i))];
          await _montarDeposito(
            tester,
            _Cola(rechazadas: mil).overrides,
            tamano: tamano,
            escala: escala,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(_textoVarias(1000)), findsOneWidget);
        });

        testWidgets('Registrar depósito · rechazada + «no pudimos enviar» juntos', (tester) async {
          final semantica = tester.ensureSemantics();
          await _montarDeposito(
            tester,
            _Cola(sinSubir: 2, rechazadas: [_dia9]).overrides,
            tamano: tamano,
            escala: escala,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(_sinSubir), findsOneWidget);
          // «Reintentar ahora» es del primero; el segundo no tiene botón.
          expect(_botonesDelAviso(_sinSubir), findsOneWidget);
          await _verAviso(tester, _rechazo);
          expect(find.byKey(_rechazo), findsOneWidget);
          expect(_botonesDelAviso(_rechazo), findsNothing);
          // Uno sobre el otro, sin tocarse (si el primero sigue armado, se miden juntos).
          if (find.byKey(_sinSubir).evaluate().isNotEmpty) {
            expect(
              tester.getRect(find.byKey(_rechazo)).top,
              greaterThanOrEqualTo(tester.getRect(find.byKey(_sinSubir)).bottom),
            );
          }
          await capturar443(tester, '38a08_rechazada_registrar_ambos_$suf');
          await _guias(tester);
          semantica.dispose();
        });

        testWidgets('Registrar depósito · rechazada + error al registrar (el error va arriba)', (
          tester,
        ) async {
          final arnes = ArnesDeDeposito()
            ..depositos.fallarUnaVezCon = const FailureDepositoNoGuardado();
          await _montarDeposito(
            tester,
            _Cola(sinSubir: 1, rechazadas: [_dia9]).overrides,
            tamano: tamano,
            escala: escala,
            arnes: arnes,
          );
          await tester.pumpAndSettle();
          await escribirMonto(tester, '1800');
          await sacarLaFoto(tester);
          await tocarRegistrar(tester);
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('deposito_error')), findsOneWidget);
          final lista = tester.getRect(find.byKey(const Key('deposito_lista')));
          final error = tester.getRect(find.byKey(const Key('deposito_error')));
          expect(error.top, greaterThanOrEqualTo(lista.top));
          expect(error.bottom, lessThanOrEqualTo(lista.bottom));
          await capturar443(tester, '38a08_rechazada_registrar_error_$suf');
          await _verAviso(tester, _rechazo);
          expect(find.byKey(_rechazo), findsOneWidget);
          // Lo tipeado no se pierde.
          await tester.drag(find.byKey(const Key('deposito_lista')), const Offset(0, 5000));
          await tester.pumpAndSettle();
          await verEnElFormulario(tester, const Key('deposito_monto'));
          final campo = tester.widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('deposito_monto')),
              matching: find.byType(TextField),
            ),
          );
          expect(campo.controller!.text, contains('1800'));
        });

        testWidgets('Registrar depósito · rechazada + sin conexión', (tester) async {
          final arnes = ArnesDeDeposito(conexion: TipoConexion.sinConexion);
          await _montarDeposito(
            tester,
            _Cola(rechazadas: [_dia9]).overrides,
            tamano: tamano,
            escala: escala,
            arnes: arnes,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('deposito_sin_conexion')), findsOneWidget);
          expect(find.byKey(_rechazo), findsOneWidget);
          await capturar443(tester, '38a08_rechazada_registrar_sin_conexion_$suf');
        });

        testWidgets('Mi Cuenta · una rechazada arriba de las tarjetas', (tester) async {
          final semantica = tester.ensureSemantics();
          await _montarCuenta(
            tester,
            _Cola(rechazadas: [_dia9]).overrides,
            RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
            tamano: tamano,
            escala: escala,
          );
          expect(tester.takeException(), isNull);
          expect(find.text(_textoUna('09/11')), findsOneWidget);
          expect(_botonesDelAviso(_rechazo), findsNothing);
          _entraEnLaPantalla(tester, _rechazo, tamano);
          await capturar443(tester, '38a08_rechazada_cuenta_una_$suf');
          await _guias(tester);
          semantica.dispose();
        });

        testWidgets('Mi Cuenta · varias rechazadas + «no pudimos enviar» juntos', (tester) async {
          final semantica = tester.ensureSemantics();
          await _montarCuenta(
            tester,
            _Cola(sinSubir: 2, rechazadas: [_dia8, _dia9]).overrides,
            RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
            tamano: tamano,
            escala: escala,
          );
          expect(tester.takeException(), isNull);
          expect(find.byKey(_sinSubir), findsOneWidget);
          expect(find.text(_textoVarias(2)), findsOneWidget);
          final arriba = tester.getRect(find.byKey(_sinSubir));
          final abajo = tester.getRect(find.byKey(_rechazo));
          expect(abajo.top, greaterThanOrEqualTo(arriba.bottom));
          await capturar443(tester, '38a08_rechazada_cuenta_ambos_$suf');
          await _guias(tester);
          semantica.dispose();
        });

        testWidgets('Mi Cuenta · cuenta nueva: chip apagado y aviso a la vez', (tester) async {
          final semantica = tester.ensureSemantics();
          await _montarCuenta(
            tester,
            _Cola(rechazadas: [_dia9]).overrides,
            RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
            tamano: tamano,
            escala: escala,
          );
          await tester.ensureVisible(find.byKey(_chip));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byKey(_rechazo), findsOneWidget);
          expect(tester.widget<OutlinedButton>(find.byKey(_chip)).onPressed, isNull);
          await capturar443(tester, '38a08_rechazada_cuenta_nueva_$suf');
          await _guias(tester);
          semantica.dispose();
        });

        testWidgets('Mi Cuenta · sin conexión + rechazada', (tester) async {
          await _montarCuenta(
            tester,
            _Cola(rechazadas: [_dia9]).overrides,
            RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
            tamano: tamano,
            escala: escala,
            conexion: TipoConexion.sinConexion,
          );
          expect(tester.takeException(), isNull);
          expect(find.byKey(_rechazo), findsOneWidget);
          await capturar443(tester, '38a08_rechazada_cuenta_sin_conexion_$suf');
        });
      });
    }
  }

  // -------- Accesibilidad del aviso ----------------------------------------------------------------
  group('accesibilidad', () {
    testWidgets('el aviso se anuncia (liveRegion) con su texto entero en un solo nodo', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montarDeposito(tester, _Cola(rechazadas: [_dia9]).overrides);
      await tester.pumpAndSettle();
      final nodo = tester.getSemantics(find.byKey(_rechazo));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      expect(nodo.label, contains('ya no se puede reintentar'));
      expect(nodo.label, contains('Avisale a tu coordinador'));
      semantica.dispose();
    });

    testWidgets('en Mi Cuenta también se anuncia', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montarCuenta(
        tester,
        _Cola(rechazadas: [_dia9]).overrides,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
      );
      final nodo = tester.getSemantics(find.byKey(_rechazo));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      semantica.dispose();
    });

    testWidgets('el aviso no suma un nodo tocable (no hay botón que anunciar)', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montarDeposito(tester, _Cola(rechazadas: [_dia9]).overrides);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(_rechazo), matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.descendant(of: find.byKey(_rechazo), matching: find.byType(GestureDetector)),
        findsNothing,
      );
      semantica.dispose();
    });
  });

  // -------- Casos límite ---------------------------------------------------------------------------
  group('casos límite', () {
    testWidgets('la lectura que falla: no hay aviso, no se cae y se puede registrar', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      await _montarDeposito(tester, _lecturaRota(), arnes: arnes);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(_rechazo), findsNothing);
      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados, hasLength(1));
    });

    testWidgets('la lectura que falla en Mi Cuenta: se ven las tarjetas y no hay aviso', (
      tester,
    ) async {
      await _montarCuenta(
        tester,
        _lecturaRota(),
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(_rechazo), findsNothing);
      expect(find.byKey(const Key('cuenta_pestana')), findsOneWidget);
    });

    testWidgets('sin base abierta (dbLocal nulo): el proveedor real no da aviso ni falla', (
      tester,
    ) async {
      // Sin override de los proveedores de tickets: corre el real, con `dbLocalProvider` en null.
      await _montarCuenta(
        tester,
        const [],
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(_rechazo), findsNothing);
    });

    testWidgets('aparece mientras la persona tipea: lo tipeado y el foco no se pierden', (
      tester,
    ) async {
      final cola = _Cola();
      await _montarDeposito(tester, cola.overrides);
      await tester.pumpAndSettle();
      await escribirMonto(tester, '1800');
      expect(find.byKey(_rechazo), findsNothing);

      await cola.rechazar(tester, [_dia9]);
      await tester.pumpAndSettle();
      expect(find.byKey(_rechazo), findsOneWidget);
      final campo = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('deposito_monto')),
          matching: find.byType(TextField),
        ),
      );
      expect(campo.controller!.text, '1800');
    });

    testWidgets('0 → 1 → 2 → 1 → 0 rechazadas: el texto sigue a la cuenta y el botón responde', (
      tester,
    ) async {
      final cola = _Cola();
      final arnes = ArnesDeDeposito();
      await _montarDeposito(tester, cola.overrides, arnes: arnes);
      await cola.rechazar(tester, [_dia9]);
      expect(find.text(_textoUna('09/11')), findsOneWidget);
      await cola.rechazar(tester, [_dia8, _dia9]);
      expect(find.text(_textoVarias(2)), findsOneWidget);
      expect(find.text(_textoUna('09/11')), findsNothing);
      await cola.rechazar(tester, [_dia8]);
      expect(find.text(_textoUna('08/11')), findsOneWidget);
      await cola.rechazar(tester, const []);
      expect(find.byKey(_rechazo), findsNothing);

      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados, hasLength(1));
    });

    testWidgets('reentrada: salir y volver a abrir «Registrar depósito» deja el aviso', (
      tester,
    ) async {
      final cola = _Cola(rechazadas: [_dia9]);
      await _montarDeposito(tester, cola.overrides);
      await tester.pumpAndSettle();
      expect(find.byKey(_rechazo), findsOneWidget);
      unawaited(tester.state<NavigatorState>(find.byType(Navigator).first).maybePop());
      await tester.pumpAndSettle();
      expect(find.text(TextosDeposito.titulo), findsNothing);
      expect(find.byKey(_rechazo), findsNothing);
      await abrirDeposito(tester);
      expect(find.byKey(_rechazo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'con los dos avisos a 360×640 y 200 %, «Registrar depósito» se alcanza y registra',
      (tester) async {
        final arnes = ArnesDeDeposito();
        await _montarDeposito(
          tester,
          _Cola(sinSubir: 3, rechazadas: [_dia8, _dia9]).overrides,
          escala: 2,
          arnes: arnes,
        );
        await tester.pumpAndSettle();
        await escribirMonto(tester, '1800');
        await verEnElFormulario(tester, const Key('deposito_destino_2'));
        await tester.tap(find.byKey(const Key('deposito_destino_2')));
        await tester.pump();
        await tocarRegistrar(tester);
        expect(tester.takeException(), isNull);
        expect(arnes.depositos.guardados, hasLength(1));
      },
    );

    testWidgets('con el teclado abierto a 360×640 y 200 %, el monto sigue a la vista con ambos', (
      tester,
    ) async {
      await _montarDeposito(
        tester,
        _Cola(sinSubir: 3, rechazadas: [_dia8, _dia9]).overrides,
        escala: 2,
      );
      await tester.pumpAndSettle();
      await verEnElFormulario(tester, const Key('deposito_monto'));
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
    });

    testWidgets('en Mi Cuenta, con el aviso, el chip «Registrar depósito» abre la pantalla', (
      tester,
    ) async {
      await _montarCuenta(
        tester,
        _Cola(rechazadas: [_dia9]).overrides,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        escala: 2,
      );
      await tester.ensureVisible(find.byKey(_chip));
      await tester.pump();
      await tester.tap(find.byKey(_chip));
      await tester.pumpAndSettle();
      expect(find.text(TextosDeposito.titulo), findsOneWidget);
      expect(find.byKey(_rechazo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('el texto no lleva códigos técnicos ni signos de más', () {
      for (final t in [
        TextosDeposito.ticketsRechazados([_dia9]),
        TextosDeposito.ticketsRechazados([_dia8, _dia9]),
      ]) {
        expect(t, isNot(contains('RECHAZADA')));
        expect(t, isNot(contains('muy_grande')));
        expect(t, isNot(contains('copia_local_ausente')));
        expect(t, isNot(contains('  ')));
        expect(t.length, lessThan(200));
      }
    });
  });

  // -------- Con la base real (Drift en memoria) ----------------------------------------------------
  group('con la base real', () {
    late AppDatabase db;
    late TicketLocalDataSourceDrift ticketsLocal;
    late RegistrarDepositoConTicketUseCase registrar;
    final ahora = DateTime.utc(2026, 11, 10, 15);

    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      final encolador = EncoladorSyncEnMemoria();
      final almacen = AlmacenDeFotosEnMemoria();
      ticketsLocal = TicketLocalDataSourceDrift(db, encolador: encolador);
      final tickets = TicketRepositoryImpl(
        ticketsLocal,
        almacen,
        logger: loggerMudo(),
        ahora: () => ahora,
      );
      final depositos = DepositoRepositoryImpl(
        DepositoLocalDataSourceDrift(db, encolador: encolador),
        logger: loggerMudo(),
      );
      registrar = RegistrarDepositoConTicketUseCase(
        transaccion: TransaccionLocalDrift(db),
        registrarTicket: RegistrarTicketUseCase(tickets, ahora: () => ahora),
        registrarDeposito: RegistrarDepositoUseCase(depositos, ahora: () => ahora),
        almacen: almacen,
        ahora: () => ahora,
      );
    });

    Future<void> depositar(String n, {DateTime? fecha}) async {
      final r = await registrar(
        RegistrarDepositoConTicketParams(
          fecha: fecha,
          depositoId: 'd-$n',
          ticketId: 't-$n',
          colportorId: 'col-1',
          montoCentavos: 100000,
          destino: DestinoDeDeposito.banco,
          concepto: ConceptoDeDeposito.casaEditora,
          foto: fotoDePrueba(),
        ),
      );
      expect(r.isRight(), isTrue);
    }

    Future<void> asentarConBase(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> cerrar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    }

    testWidgets('Mi Cuenta: el rechazo aparece solo, el coordinador lo valida y se va', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await depositar('1', fecha: _dia9);
      });
      final db0 = db;
      await _montarCuenta(tester, [
        dbLocalProvider.overrideWithValue(db0),
      ], RepositorioDeCuentaControlable(inicial: resumenDelCanvas));
      await asentarConBase(tester);
      expect(find.byKey(_rechazo), findsNothing, reason: 'la foto espera su primer intento');

      await tester.runAsync(
        () => ticketsLocal.anotarIntentoFallido('t-1', codigo: 'muy_grande', definitivo: true),
      );
      await asentarConBase(tester);
      expect(find.text(_textoUna('09/11')), findsOneWidget);
      expect(find.byKey(_sinSubir), findsNothing);

      // El coordinador lo valida: ya lo revisó.
      await tester.runAsync(
        () => (db0.update(
          db0.depositos,
        )..where((d) => d.id.equals('d-1'))).write(DepositosCompanion(validadoEn: Value(ahora))),
      );
      await asentarConBase(tester);
      expect(find.byKey(_rechazo), findsNothing);
      expect(tester.takeException(), isNull);
      await cerrar(tester);
    });

    testWidgets('Registrar depósito: llega una rechazada con la pantalla abierta y se alcanza', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await depositar('1', fecha: _dia9);
        await depositar('2', fecha: _dia8);
      });
      final db0 = db;
      await _montarDeposito(tester, [dbLocalProvider.overrideWithValue(db0)]);
      await asentarConBase(tester);
      expect(find.byKey(_rechazo), findsNothing);

      await tester.runAsync(
        () => ticketsLocal.anotarIntentoFallido(
          't-1',
          codigo: 'copia_local_ausente',
          definitivo: true,
        ),
      );
      await asentarConBase(tester);
      expect(find.text(_textoUna('09/11')), findsOneWidget);

      await tester.runAsync(
        () => ticketsLocal.anotarIntentoFallido('t-2', codigo: 'muy_grande', definitivo: true),
      );
      await asentarConBase(tester);
      expect(find.text(_textoVarias(2)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cerrar(tester);
    });

    testWidgets('de «lo reintentamos solo» a «ya no se puede»: un aviso cede al otro', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await depositar('1', fecha: _dia9);
        await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'red', definitivo: false);
      });
      final db0 = db;
      await _montarDeposito(tester, [dbLocalProvider.overrideWithValue(db0)]);
      await asentarConBase(tester);
      expect(find.byKey(_sinSubir), findsOneWidget);
      expect(find.byKey(_rechazo), findsNothing);

      await tester.runAsync(
        () => ticketsLocal.anotarIntentoFallido('t-1', codigo: 'muy_grande', definitivo: true),
      );
      await asentarConBase(tester);
      expect(find.byKey(_sinSubir), findsNothing);
      expect(find.text(_textoUna('09/11')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cerrar(tester);
    });

    testWidgets('el motivo técnico de la falla no sale en pantalla', (tester) async {
      await tester.runAsync(() async {
        await depositar('1', fecha: _dia9);
        await ticketsLocal.anotarIntentoFallido(
          't-1',
          codigo: 'Pedro Pérez 099123456 pedro@correo.uy',
          definitivo: true,
        );
      });
      final db0 = db;
      await _montarCuenta(tester, [
        dbLocalProvider.overrideWithValue(db0),
      ], RepositorioDeCuentaControlable(inicial: resumenDelCanvas));
      await asentarConBase(tester);
      expect(find.byKey(_rechazo), findsOneWidget);
      expect(find.textContaining('099123456'), findsNothing);
      expect(find.textContaining('pedro@'), findsNothing);
      await cerrar(tester);
    });

    testWidgets('el depósito borrado en el teléfono saca el aviso', (tester) async {
      await tester.runAsync(() async {
        await depositar('1', fecha: _dia9);
        await ticketsLocal.anotarIntentoFallido('t-1', codigo: 'muy_grande', definitivo: true);
      });
      final db0 = db;
      await _montarCuenta(tester, [
        dbLocalProvider.overrideWithValue(db0),
      ], RepositorioDeCuentaControlable(inicial: resumenDelCanvas));
      await asentarConBase(tester);
      expect(find.byKey(_rechazo), findsOneWidget);
      await tester.runAsync(
        () => (db0.update(
          db0.depositos,
        )..where((d) => d.id.equals('d-1'))).write(DepositosCompanion(deletedAt: Value(ahora))),
      );
      await asentarConBase(tester);
      expect(find.byKey(_rechazo), findsNothing);
      await cerrar(tester);
    });
  });
}

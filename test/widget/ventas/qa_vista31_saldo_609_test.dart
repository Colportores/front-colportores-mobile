// QA de «Devoluciones: nunca queda plata a favor del cliente» (vista 31, HU-VEN-004, #609, PR #631).
// Complementa a `qa_vista31_devolucion_161_test.dart` (matriz de estados, escenarios y casos límite del
// implementador, que ya cubre los 31-0x vigentes y el estado «venta saldada»): acá van los bordes de la
// regla nueva, el cruce con otro cobro a mitad de la devolución, el orden entre «saldada», «fuera de
// plazo» y «ya devuelta», lo que se ve con letra grande y un recorrido de punta a punta contra la base
// real (Drift en memoria). Los hallazgos van con `skip` y se corren con `--dart-define=QA_HALLAZGOS=true`;
// las capturas con `--dart-define=QA_CAPTURAS=true`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/devolucion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/repositories/devolucion_repository_impl.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/devolucion_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/devolucion_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/qa_vista31_devolucion_161_arnes.dart';
import '../../helpers/venta_falsos.dart';
import '../../helpers/venta_ui_falsos.dart';

String _m(int centavos) => FormatoVenta.monto(centavos);

const _textoSaldada = 'Esta venta ya está saldada: el cliente pagó todo lo que se queda comprando';

/// La venta del canvas con «Nuestros Hijos» elegido y «Seguir» tocado.
Future<Montaje161> _hastaSeguir(
  WidgetTester tester,
  RepoFalso161 repo, {
  Size tamano = chico161,
  double escala = 1,
}) async {
  final m = await montar161(tester, repo, tamano: tamano, escala: escala);
  await tocar(tester, mas161('Nuestros Hijos'));
  await tocar(tester, cta161);
  return m;
}

/// Un repositorio que, al registrar, deja la venta saldada por «otro cobro» y contesta lo que dice el
/// servidor (`23514`): la venta se vuelve a leer saldada.
RepoFalso161 _repoQueSeSaldaAlRegistrar() {
  final repo = RepoFalso161(ventaCanvas161());
  repo.respuestas.add(() async {
    repo.venta = ventaCanvas161(cobrado: 450000);
    return const Left(FailureDevolucionVentaSaldada());
  });
  return repo;
}

void main() {
  group('La regla en el borde: lo devuelto contra el saldo', () {
    testWidgets(
      'lo devuelto cabe justo en el saldo: saldo 0 y NO hay aviso de plata sin devolver',
      (tester) async {
        // Pagó $ 2.600 de $ 4.500: devuelve el de $ 1.900 y se queda con $ 2.600, justo lo pagado.
        await _hastaSeguir(tester, RepoFalso161(ventaCanvas161(cobrado: 260000)));

        expect(find.byKey(const Key('devolucion_sin_devolver')), findsNothing);
        expect(find.text('Saldo nuevo'), findsOneWidget);
        expect(find.text(_m(0)), findsWidgets);
        expect(boton161(tester).onPressed, isNotNull);
      },
    );

    testWidgets('un peso de más ya se avisa, con el monto exacto y en pesos con coma', (
      tester,
    ) async {
      // Pagó $ 2.600,50: sobran $ 0,50 sobre lo que se queda.
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161(cobrado: 260050)));

      expect(
        find.text(
          'Ya pagó ${_m(50)} más de lo que se queda. Ese dinero no se devuelve: la venta queda '
          'saldada y nada queda a favor del cliente.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('«Ya pagó» de la tarjeta no se muestra cuando no pagó nada, y no hay aviso', (
      tester,
    ) async {
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161(cobrado: 0)));

      expect(find.text('Ya pagó'), findsNothing);
      expect(find.byKey(const Key('devolucion_sin_devolver')), findsNothing);
    });

    testWidgets('pagó casi todo (\$ 4.499): sigue habiendo qué devolver y el aviso dice \$ 1.899', (
      tester,
    ) async {
      final m = await montar161(tester, RepoFalso161(ventaCanvas161(cobrado: 449900)));
      expect(find.byKey(const Key('devolucion_saldada')), findsNothing);
      await tocar(tester, mas161('Nuestros Hijos'));
      await tocar(tester, cta161);

      expect(find.textContaining('Ya pagó ${_m(189900)} más de lo que se queda'), findsOneWidget);
      expect(m.resultados, isEmpty);
    });

    testWidgets(
      'pagó de más por un cobro duplicado (\$ 5.000 de \$ 4.500): saldada, sin dejar seguir',
      (tester) async {
        await montar161(tester, RepoFalso161(ventaCanvas161(cobrado: 500000)));

        expect(find.byKey(const Key('devolucion_saldada')), findsOneWidget);
        expect(find.text('Seguir'), findsNothing);
      },
    );

    testWidgets('el subtítulo de la venta con saldo muestra lo pagado contra lo que se queda', (
      tester,
    ) async {
      await montar161(tester, RepoFalso161(ventaCanvas161(cobrado: 330000)));

      expect(find.text('María Fernández · pagó ${_m(330000)} de ${_m(450000)}'), findsOneWidget);
    });
  });

  group('Orden de las pantallas: saldada, fuera de plazo, ya devuelta', () {
    testWidgets('saldada Y pasadas las 72 h: dice «saldada», no el plazo (como el servidor)', (
      tester,
    ) async {
      await montar161(
        tester,
        RepoFalso161(ventaCanvas161(cobrado: 450000)),
        ahora: fechaDeLaVenta161.add(const Duration(hours: 100)),
      );

      expect(find.byKey(const Key('devolucion_saldada')), findsOneWidget);
      expect(find.byKey(const Key('devolucion_fuera_de_plazo')), findsNothing);
      expect(find.textContaining(_textoSaldada), findsOneWidget);
    });

    testWidgets('con saldo y pasadas las 72 h: sigue diciendo el plazo', (tester) async {
      await montar161(
        tester,
        RepoFalso161(ventaCanvas161()),
        ahora: fechaDeLaVenta161.add(const Duration(hours: 100)),
      );

      expect(find.byKey(const Key('devolucion_fuera_de_plazo')), findsOneWidget);
      expect(find.byKey(const Key('devolucion_saldada')), findsNothing);
    });

    testWidgets('ya devuelta por completo y pagada: dice «ya se devolvió», no «saldada»', (
      tester,
    ) async {
      await montar161(tester, RepoFalso161(ventaCanvas161(cobrado: 450000, salud: 1, hijos: 1)));

      expect(find.byKey(const Key('devolucion_ya_devuelta')), findsOneWidget);
      expect(find.byKey(const Key('devolucion_saldada')), findsNothing);
    });

    testWidgets('devuelta a medias y lo que queda está pagado: saldada, con la cuenta que queda', (
      tester,
    ) async {
      // Ya volvió «Nuestros Hijos» ($ 1.900); se queda con $ 2.600 y pagó $ 2.600.
      await montar161(tester, RepoFalso161(ventaCanvas161(cobrado: 260000, hijos: 1)));

      expect(find.byKey(const Key('devolucion_saldada')), findsOneWidget);
      expect(find.textContaining(_textoSaldada), findsOneWidget);
      expect(find.byKey(const Key('devolucion_fila_i-salud')), findsNothing);
    });

    testWidgets('la pantalla de saldada no ofrece nada que no pueda hacer: solo «Volver»', (
      tester,
    ) async {
      final m = await montar161(tester, RepoFalso161(ventaCanvas161(cobrado: 450000)));

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Volver'), findsWidgets);
      await tocar(tester, find.byKey(const Key('devolucion_volver')));
      expect(m.resultados, [false]);
    });
  });

  group('Otro cobro salda la venta mientras se arma la devolución', () {
    testWidgets('al registrar: la pantalla pasa a «saldada», sin spinner ni botón trabado', (
      tester,
    ) async {
      final repo = _repoQueSeSaldaAlRegistrar();
      final m = await _hastaSeguir(tester, repo);
      await confirmarEnLaHoja161(tester);

      expect(find.byKey(const Key('devolucion_saldada')), findsOneWidget);
      expect(find.text('Registrando…'), findsNothing);
      expect(find.byKey(const Key('devolucion_listo')), findsNothing);
      expect(repo.pedidos, hasLength(1));
      expect(m.resultados, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Volver» de esa pantalla cierra sin registrar', (tester) async {
      final m = await _hastaSeguir(tester, _repoQueSeSaldaAlRegistrar());
      await confirmarEnLaHoja161(tester);

      await tocar(tester, find.byKey(const Key('devolucion_volver')));
      expect(m.resultados, [false]);
    });

    testWidgets('si la relectura falla, no queda sin salida: aviso y «Reintentar» a mano', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      repo.respuestas.add(() async {
        repo.fallaAlLeer = const FailureDevolucionNoDisponible();
        return const Left(FailureDevolucionVentaSaldada());
      });
      await _hastaSeguir(tester, repo);
      await confirmarEnLaHoja161(tester);

      expect(find.byKey(const Key('devolucion_error')), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(boton161(tester).onPressed, isNotNull);
      expect(find.text('Registrando…'), findsNothing);
    });

    testWidgets('lo tipeado no se pierde si el rechazo no era por saldada (otra falla)', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161());
      repo.respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'qa')));
      await _hastaSeguir(tester, repo);
      await escribir(tester, motivo161, 'Se arrepintió');
      await confirmarEnLaHoja161(tester);

      expect(find.byKey(const Key('devolucion_error')), findsOneWidget);
      expect(find.text('Se arrepintió'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets(
      'el atrás del sistema desde esa pantalla no pregunta «¿Descartar lo que escribiste?»',
      (tester) async {
        final m = await _hastaSeguir(tester, _repoQueSeSaldaAlRegistrar());
        await escribir(tester, motivo161, 'Se arrepintió');
        await confirmarEnLaHoja161(tester);
        expect(find.byKey(const Key('devolucion_saldada')), findsOneWidget);

        await tester.binding.handlePopRoute();
        await asentar(tester);

        // Lo escrito ya no se ve ni se puede registrar: preguntar si se descarta es ruido.
        expect(find.text('¿Descartar lo que escribiste?'), findsNothing);
        expect(m.resultados, [false]);
      },
      // skip: issue #609 (QA) — con la venta ya saldada quedan `_elegidas` y el motivo; el atrás del
      // sistema (y la flecha) preguntan «¿Descartar lo que escribiste?» sobre una pantalla sin nada editable.
      skip: !conHallazgos161,
    );
  });

  group('Letra grande (2,0) a 360×640: lo que dice el aviso se alcanza a ver', () {
    testWidgets(
      'el aviso «Ya pagó \$ X más» queda dentro de la pantalla tras tocar «Seguir»',
      (tester) async {
        await _hastaSeguir(tester, RepoFalso161(ventaCanvas161(cobrado: 330000)), escala: 2);
        expect(tester.takeException(), isNull);

        // La lista es perezosa: si el aviso quedó bajo el pliegue ni siquiera está armado.
        expect(
          find.byKey(const Key('devolucion_sin_devolver')).hitTestable(),
          findsOneWidget,
          reason:
              'el aviso de la plata que no se devuelve queda bajo el pliegue: hay que bajar la lista',
        );
      },
      // skip: issue #609 (QA) — a 360×640 con letra al 200 % el aviso de que $ 700 no se devuelven
      // queda fuera de vista tras «Seguir» y nada lleva hasta él.
      skip: !conHallazgos161,
    );

    testWidgets('la hoja de confirmar repite el saldo nuevo y alcanza con el botón visible a 2,0', (
      tester,
    ) async {
      await _hastaSeguir(tester, RepoFalso161(ventaCanvas161(cobrado: 330000)), escala: 2);
      await tocar(tester, cta161);

      expect(find.byKey(const Key('devolucion_hoja')), findsOneWidget);
      expect(find.text('Saldo nuevo'), findsWidgets);
      expect(find.byKey(const Key('devolucion_hoja_registrar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Doble acción y reentrada con la regla nueva', () {
    testWidgets('dos «Registrar devolución» seguidos en la hoja registran una sola vez', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161(cobrado: 330000));
      await _hastaSeguir(tester, repo);
      await tocar(tester, cta161);
      await tester.tap(find.byKey(const Key('devolucion_hoja_registrar')));
      await tester.tap(find.byKey(const Key('devolucion_hoja_registrar')), warnIfMissed: false);
      await asentar(tester);

      expect(repo.pedidos, hasLength(1));
    });

    testWidgets('registrada una devolución que pasa del saldo: el resumen dice saldo 0', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161(cobrado: 330000));
      await _hastaSeguir(tester, repo);
      await confirmarEnLaHoja161(tester);

      final resumen = find.byKey(const Key('devolucion_resumen'));
      expect(resumen, findsOneWidget);
      expect(find.descendant(of: resumen, matching: find.text(_m(0))), findsOneWidget);
      expect(find.descendant(of: resumen, matching: find.text(_m(260000))), findsOneWidget);
      expect(find.text('Debo al cliente'), findsNothing);
    });

    testWidgets('reentrar a la venta que esa devolución dejó saldada: dice «saldada»', (
      tester,
    ) async {
      final repo = RepoFalso161(ventaCanvas161(cobrado: 330000));
      final m = await _hastaSeguir(tester, repo);
      await confirmarEnLaHoja161(tester);
      await tocar(tester, find.byKey(const Key('devolucion_listo')));
      expect(m.resultados, [true]);

      // La venta, ahora, con «Nuestros Hijos» devuelto: se queda con $ 2.600 y pagó $ 3.300.
      repo.venta = ventaCanvas161(cobrado: 330000, hijos: 1);
      await tocar(tester, find.byKey(const Key('abrir')));
      expect(find.byKey(const Key('devolucion_saldada')), findsOneWidget);
    });
  });

  group('De punta a punta contra la base real (Drift en memoria)', () {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    late AppDatabase db;
    late EncoladorSyncEnMemoria encolador;
    late DevolucionLocalDataSourceDrift local;
    late VentaLocalDataSourceDrift ventas;
    late CobranzaLocalDataSourceDrift cobranzas;

    Future<void> cobrar(WidgetTester tester, int monto, {String id = 'c-1'}) => tester.runAsync(
      () => cobranzas.registrar(
        Cobranza(
          id: id,
          ventaId: 'v-1',
          montoCentavos: monto,
          medio: MedioCobranza.efectivo,
          fecha: fechaDeLaVenta161,
          auditoria: Auditoria(createdAt: ahora161, updatedAt: ahora161, createdBy: 'col-1'),
        ),
      ),
    );

    Future<void> prepararBase(WidgetTester tester, {required int cobrado}) async {
      await tester.runAsync(() async {
        db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
        encolador = EncoladorSyncEnMemoria();
        final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
        local = DevolucionLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
        ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
        cobranzas = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
        await sembrarCasa(db);
        await ventas.registrar(ventaDe('v-1', monto: 450000, fecha: fechaDeLaVenta161), [
          itemDe('i-salud', 'v-1', productoId: 'p-salud', cantidad: 1, precio: 260000),
          itemDe('i-hijos', 'v-1', productoId: 'p-hijos', cantidad: 1, precio: 190000),
        ]);
      });
      if (cobrado > 0) await cobrar(tester, cobrado);
      encolador.encolados.clear();
    }

    Future<void> cerrarBase(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    }

    Finder masDeHijos() => find.descendant(
      of: find.byKey(const Key('devolucion_fila_i-hijos')),
      matching: find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').startsWith('Uno más'),
      ),
    );

    Future<void> abrir(WidgetTester tester) async {
      tester.view.physicalSize = chico161;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final resultados = <bool?>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            devolucionRepositoryProvider.overrideWithValue(DevolucionRepositoryImpl(local)),
            relojDevolucionProvider.overrideWithValue(() => ahora161),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('abrir'),
                  onPressed: () async {
                    resultados.add(
                      await DevolucionPage.abrir(
                        context,
                        ventaId: 'v-1',
                        colportorId: 'col-1',
                        espacioId: 'esp-1',
                      ),
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await asentar(tester);
    }

    testWidgets(
      'pagó \$ 3.300 de \$ 4.500 y devuelve el de \$ 1.900: queda saldo 0, el cobro intacto',
      (tester) async {
        await prepararBase(tester, cobrado: 330000);
        await abrir(tester);
        await tocar(tester, masDeHijos());
        await tocar(tester, cta161);
        expect(find.byKey(const Key('devolucion_sin_devolver')), findsOneWidget);

        await tocar(tester, cta161);
        await tester.tap(find.byKey(const Key('devolucion_hoja_registrar')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await asentar(tester);
        expect(find.byKey(const Key('devolucion_resumen')), findsOneWidget);

        final saldo = await tester.runAsync(() async => (await cobranzas.ventaConSaldo('v-1')));
        expect(saldo!.saldoCentavos, 0);
        expect(saldo.cobradoCentavos, 330000);
        expect(saldo.seQuedaConCentavos, 260000);
        final cola = [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];
        expect(cola, contains('devolucion:insert'));
        await cerrarBase(tester);
      },
    );

    testWidgets(
      'otro cobro salda la venta con la pantalla abierta: el rechazo real lleva a «saldada»',
      (tester) async {
        await prepararBase(tester, cobrado: 100000);
        await abrir(tester);
        await tocar(tester, masDeHijos());
        await tocar(tester, cta161);

        // Mientras tanto la cliente paga todo lo que faltaba.
        await cobrar(tester, 350000, id: 'c-2');

        await tocar(tester, cta161);
        await tester.tap(find.byKey(const Key('devolucion_hoja_registrar')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await asentar(tester);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await asentar(tester);

        expect(find.byKey(const Key('devolucion_saldada')), findsOneWidget);
        final filas = await tester.runAsync(() => db.select(db.devoluciones).get());
        expect(filas, isEmpty);
        await cerrarBase(tester);
      },
    );
  });
}

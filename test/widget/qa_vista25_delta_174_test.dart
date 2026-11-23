// QA de la vista 25 (#174, PR #489), segunda ronda sobre ad7b2cf: lo que cambió desde 748ad2f.
//
// - La fila «Sincronización y respaldo» de Configuración con el texto al 200 % (ae540e9): ninguna
//   palabra se parte en ningún tamaño.
// - Las hojas 25-07 y 25-09 con la barra de gestos del sistema (ad7b2cf, `mostrarHojaInferior`):
//   sus botones quedan sobre la barra, sin overflow y con las guías de accesibilidad.
// - Decisión del 10/11 sobre «Reintentar» y la unión de duplicados ya deshecha (#688, P1): la
//   operación rechazada no se vuelve a mandar. Va con `skip` (hallazgo).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/configuracion/presentation/pages/configuracion_page.dart';
import 'package:colportores_mobile/features/sincronizacion/data/services/servicio_sincronizacion_motor.dart';
import 'package:colportores_mobile/features/sincronizacion/domain/entities/estado_sincronizacion.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/textos_sincronizacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../helpers/qa_vista25_174_arnes.dart';
import '../helpers/sincronizacion_falsos.dart';

/// Cada palabra del texto [texto] entra entera en el ancho que le dio el diseño.
void _sinPalabraPartida(WidgetTester tester, Finder dentro, String texto) {
  final cuadro = tester.renderObject<RenderParagraph>(
    find.descendant(of: dentro, matching: find.text(texto)),
  );
  final ancho = cuadro.constraints.maxWidth;
  for (final palabra in texto.split(' ')) {
    final medida = TextPainter(
      text: TextSpan(text: palabra, style: cuadro.text.style),
      textDirection: TextDirection.ltr,
      textScaler: cuadro.textScaler,
    )..layout();
    expect(
      medida.width,
      lessThanOrEqualTo(ancho + 0.5),
      reason:
          '«$palabra» mide ${medida.width.toStringAsFixed(1)} dp y la fila le da '
          '${ancho.toStringAsFixed(1)} dp: se parte',
    );
  }
}

Future<void> _abrirConfiguracion(WidgetTester tester, Size tam, double escala) async {
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = TelefonoSync();
  await tester.pumpWidget(
    ProviderScope(
      overrides: t.overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const ConfiguracionPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final fila = find.byKey(const Key('configuracion_sincronizacion'));
  await tester.scrollUntilVisible(fila, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

/// La barra de gestos de Android (48 dp) abajo: la hoja no puede dejar sus botones debajo.
void _barraDeGestos(WidgetTester tester, {double alto = 48}) {
  tester.view.padding = FakeViewPadding(bottom: alto);
  tester.view.viewPadding = FakeViewPadding(bottom: alto);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

/// Un hallazgo que se corre con `--dart-define=QA_HALLAZGOS=true`.
const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  group('Configuración › fila «Sincronización y respaldo» (ae540e9)', () {
    Future<void> comprobar(WidgetTester tester, Size tam, double escala) async {
      final semantica = tester.ensureSemantics();
      await cargarFuentes25(tester);
      await _abrirConfiguracion(tester, tam, escala);
      await capturar25(tester, 'delta_config_${tam.width.toInt()}x${tam.height.toInt()}_x$escala');
      final fila = find.byKey(const Key('configuracion_sincronizacion'));

      expect(tester.takeException(), isNull, reason: 'sin overflow');
      _sinPalabraPartida(tester, fila, TextosSincronizacion.filaConfiguracion);
      _sinPalabraPartida(tester, fila, TextosSincronizacion.filaConfiguracionDetalle);
      final caja = tester.getRect(fila);
      expect(caja.height, greaterThanOrEqualTo(48));
      expect(caja.right, lessThanOrEqualTo(tam.width));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantica.dispose();
    }

    for (final tam in tamanos25) {
      for (final escala in escalas25) {
        testWidgets(
          'dado ${tam.width.toInt()}×${tam.height.toInt()} con texto al ${(escala * 100).toInt()} %, '
          'la fila no parte ninguna palabra, no desborda y se puede tocar',
          (tester) => comprobar(tester, tam, escala),
        );
      }
    }

    testWidgets(
      'dado 320×568 con texto al 200 %, la fila no parte «Sincronización»',
      (tester) => comprobar(tester, const Size(320, 568), 2.0),
      // skip: QA #174 — a 320×568 con el texto al 200 % «Sincronización» (215,7 dp) no entra en los
      // 184 dp de la fila y se parte (menor, fuera de los tamaños del proyecto).
      skip: !_conHallazgos,
    );
  });

  group('hojas con la barra de gestos del sistema (ad7b2cf)', () {
    for (final tam in tamanos25) {
      for (final escala in escalas25) {
        for (final e in [Estado25.a07Detalle, Estado25.detalleLargo, Estado25.a09HojaDatos]) {
          testWidgets('dado ${e.name} · ${tam.width.toInt()}×${tam.height.toInt()} · texto '
              '${(escala * 100).toInt()} % con barra de 48 dp, los botones de la hoja quedan sobre '
              'la barra, sin overflow y con las guías', (tester) async {
            final semantica = tester.ensureSemantics();
            _barraDeGestos(tester);
            await llegar25(tester, e, tamano: tam, escala: escala);
            // `llegar25` no toca el padding del view: lo dejamos puesto de antes.
            await tester.pump(const Duration(milliseconds: 400));

            expect(tester.takeException(), isNull, reason: 'sin overflow');
            final botones = e == Estado25.a09HojaDatos
                ? [
                    find.byKey(const Key('sincronizacion_datos_actualizar_igual')),
                    find.byKey(const Key('sincronizacion_datos_esperar')),
                  ]
                : [
                    find.byKey(const Key('sincronizacion_detalle_reintentar')),
                    find.byKey(const Key('sincronizacion_detalle_cerrar')),
                  ];
            for (final b in botones) {
              expect(b, findsOneWidget);
              await tester.ensureVisible(b);
              await tester.pump();
              final r = tester.getRect(b);
              expect(
                r.bottom,
                lessThanOrEqualTo(tam.height - 48 + 0.5),
                reason: 'el botón queda debajo de la barra de gestos',
              );
              expect(r.top, greaterThanOrEqualTo(0));
            }
            await capturar25(
              tester,
              'delta_hoja_${e.name}_${tam.width.toInt()}x${tam.height.toInt()}_x$escala',
            );
            await guias25(tester);
            semantica.dispose();
          });
        }
      }
    }

    testWidgets(
      'dado la hoja del detalle abierta con la barra, cuando toco «Reintentar», reencola esa '
      'operación y la hoja se cierra',
      (tester) async {
        _barraDeGestos(tester);
        final t = await llegar25(tester, Estado25.a07Detalle);
        await tester.tap(find.byKey(const Key('sincronizacion_detalle_reintentar')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(t.servicio.reintentos, ['op-1']);
        expect(find.byKey(const Key('sincronizacion_hoja_detalle')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('la unión de duplicados rechazada y «Reintentar» (decisión del 10/11, #688 P1)', () {
    // El trabajo «marcar como duplicado» que el servidor rechazó (UB003) queda `INVALID` y se ve en
    // la lista como un «Cambio». Cuando el teléfono ya deshizo la unión (`ubicacion_union_local` en
    // `DESHECHA`), «Reintentar» y «Reintentar las N» no lo pueden volver a mandar: el servidor
    // uniría lo que el teléfono separó.
    SpecRegistry registro() => SpecRegistry(
      [SyncSpec.push('ubicacion'), SyncSpec.push('venta')],
      allEntities: {'ubicacion', 'venta'},
    );

    Future<({SyncEngine motor, ServicioSincronizacionMotor servicio})> armar() async {
      final transport = FakeSyncTransport()
        ..seed('ubicacion', [
          {'id': 'ub-a'},
          {'id': 'ub-b'},
        ])
        ..rejectJob('op-union', 'UB003')
        ..rejectJob('op-venta', '23514');
      final motor = SyncEngine(
        specs: registro(),
        transport: transport,
        jobs: InMemoryJobStore(),
        store: InMemoryLocalStore(),
        connectivity: FakeConnectivityPort(),
      );
      await motor.stage('ubicacion', Op.marcarComoDuplicado, const {
        'duplicada_id': 'ub-b',
        'conservada_id': 'ub-a',
      }, clientOpId: 'op-union');
      await motor.stage('venta', Op.insert, const {'id': 'v-1'}, clientOpId: 'op-venta');
      await motor.syncNow();
      addTearDown(motor.dispose);
      return (motor: motor, servicio: ServicioSincronizacionMotor(motor));
    }

    test('dado una unión rechazada y una venta rechazada, ambas salen en la lista, la unión como '
        '«Cambio»', () async {
      final b = await armar();
      final lista = await b.servicio.operacionesFallidas();
      expect(lista.map((o) => o.tabla).toSet(), {'ubicacion', 'venta'});
      expect(lista.firstWhere((o) => o.tabla == 'ubicacion').tipo, TipoOperacion.cambio);
      expect((await b.motor.statusNow()).invalid, 2);
    });

    test(
      'dado una unión rechazada cuyo par el teléfono ya separó, cuando toco «Reintentar» en esa '
      'operación, no vuelve a la cola de envío',
      () async {
        final b = await armar();
        final union = (await b.servicio.operacionesFallidas()).firstWhere(
          (o) => o.tabla == 'ubicacion',
        );

        await b.servicio.reintentarFallidas(id: union.id);

        final estado = await b.motor.statusNow();
        expect(estado.pending, 0, reason: 'la unión deshecha no se reencola');
        expect(estado.invalid, 2, reason: 'sigue visible en la lista');
      },
      // skip: QA #174 — «Reintentar» reencola la unión de duplicados que el teléfono ya deshizo
      // (decisión del 10/11, #688 P1: «en #489 antes de su merge»).
      skip: !_conHallazgos,
    );

    test(
      'dado una unión rechazada ya deshecha y una venta rechazada, cuando toco «Reintentar las N», '
      'solo la venta vuelve a la cola',
      () async {
        final b = await armar();

        final n = await b.servicio.reintentarFallidas();

        final estado = await b.motor.statusNow();
        expect(n, 1, reason: 'solo la venta');
        expect(estado.pending, 1);
        expect(estado.invalid, 1, reason: 'la unión sigue rechazada y visible');
      },
      // skip: QA #174 — «Reintentar las N» reencola también la unión de duplicados deshecha
      // (decisión del 10/11, #688 P1: «en #489 antes de su merge»).
      skip: !_conHallazgos,
    );
  });
}

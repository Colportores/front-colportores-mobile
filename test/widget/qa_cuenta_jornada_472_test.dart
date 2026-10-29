// QA de «Terminar jornada» en la pantalla de la cuenta restringida (#472, PR #555; decisión de
// Cristian, 25/10, «Jornada susp.»; vista 18 + HU-JOR-002). Complementa los tests del PR con lo que
// ellos no miran: las guías de accesibilidad de Flutter, el tamaño grande (412×915), el reloj que
// avanza con la pantalla abierta, lo elegido que no se pierde tras una falla, los casos de
// superposición y las capturas (con `--dart-define=QA_CAPTURAS=true`, a `.dart_tool/qa_capturas/`,
// gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/jornada/domain/jornada_sin_cerrar.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/entrevista_falsos.dart';
import '../helpers/qa_baja_205_arnes.dart' show cargarFuentes205;
import '../helpers/terminar_jornada_cuenta_arnes.dart';

const _capturas = bool.fromEnvironment('QA_CAPTURAS');
final _raiz = GlobalKey();

final _boton = find.byKey(const Key('cuenta_terminar_jornada_boton'));
final _filaFin = find.byKey(const Key('jornada_ajustar_hora_fin'));
final _errorFin = find.byKey(const Key('jornada_error_fin'));
final _resumen = find.byKey(const Key('jornada_resumen'));
const _tamanos = [Size(360, 640), Size(412, 915)];
const _escalas = [1.0, 2.0];
const _estados = <(String, EstadoCuenta?)>[
  ('suspendida', EstadoCuenta.suspendida),
  ('pendiente', EstadoCuenta.pendienteAsignacion),
  ('sin estado conocido', null),
];

late LocalDeJornada _local;
late MontajeEntrevista _montaje;
late DateTime _reloj;

/// Como `montarCuentaConJornada` del PR, pero con el reloj que se puede mover y una raíz para
/// capturar.
Future<void> _montar(
  WidgetTester tester, {
  EstadoCuenta? estado = EstadoCuenta.suspendida,
  Size tamano = const Size(360, 640),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sesionProvider.overrideWith(SesionFijaDeLaCuenta.new),
        jornadaLocalDataSourceProvider.overrideWithValue(_local),
        disparadorBackupProvider.overrideWithValue(BackupFalsoDeLaCuenta()),
        relojJornadaProvider.overrideWithValue(() => _reloj),
        ..._montaje.overrides,
      ],
      child: RepaintBoundary(
        key: _raiz,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: estado == null
              ? const EsperandoAsignacionPage(falla: FailureSinConexion())
              : EsperandoAsignacionPage(estado: estado),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_capturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/472_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<void> _tocarTerminar(WidgetTester tester) async {
  await tester.ensureVisible(_boton);
  await tester.tap(_boton);
  await tester.pumpAndSettle();
}

Future<void> _elegirMinutosAntes(WidgetTester tester, int n) async {
  await tester.ensureVisible(_filaFin);
  await tester.tap(_filaFin);
  await tester.pumpAndSettle();
  for (var i = 0; i < n; i++) {
    await tester.tap(find.byKey(const Key('hoja_hora_menos')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('hoja_hora_usar')));
  await tester.pumpAndSettle();
}

VoidCallback? _alTocar(WidgetTester tester) => tester.widget<FilledButton>(_boton).onPressed;

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  setUp(() {
    _montaje = MontajeEntrevista();
    _reloj = ahoraDeLaCuenta;
    _local = LocalDeJornada([jornadaAbiertaDesde(DateTime(2026, 10, 23, 13, 15))]);
  });

  group('accesibilidad: las cuatro guías de Flutter, con la sección a la vista', () {
    for (final (nombre, estado) in _estados) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          final cuando =
              '$nombre · ${tamano.width.toInt()}×${tamano.height.toInt()} · '
              'texto ${(escala * 100).toInt()} %';

          testWidgets('en reposo · $cuando', (tester) async {
            await _montar(tester, estado: estado, tamano: tamano, escala: escala);
            await tester.ensureVisible(_boton);
            await tester.pumpAndSettle();

            await _guias(tester);
          });

          testWidgets('con el aviso de falla · $cuando', (tester) async {
            _local.errorAlFinalizar = StateError('disco lleno');
            await _montar(tester, estado: estado, tamano: tamano, escala: escala);
            await _tocarTerminar(tester);
            await tester.ensureVisible(_errorFin);
            await tester.pumpAndSettle();

            await _guias(tester);
          });

          testWidgets('mientras guarda («Terminando…») · $cuando', (tester) async {
            _local.demoraFinalizar = Completer<void>();
            await _montar(tester, estado: estado, tamano: tamano, escala: escala);
            await tester.ensureVisible(_boton);
            await tester.tap(_boton);
            await tester.pump(const Duration(milliseconds: 50));

            await _guias(tester);
            _local.demoraFinalizar!.complete();
            await tester.pumpAndSettle();
          });
        }
      }
    }

    testWidgets('el aviso de falla es una región viva: el lector lo anuncia solo', (tester) async {
      _local.errorAlFinalizar = StateError('disco lleno');
      await _montar(tester);
      await _tocarTerminar(tester);

      final vivas = find.descendant(
        of: _errorFin,
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      );
      expect(vivas, findsWidgets);
    });

    testWidgets('el botón y la fila de la hora tienen nombre y acción para el lector', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);
      await tester.ensureVisible(_boton);

      expect(
        tester.getSemantics(_boton),
        isSemantics(label: 'Terminar jornada', isButton: true, hasTapAction: true, isEnabled: true),
      );
      final fila = tester.getSemantics(_filaFin);
      expect(fila.label, contains('HORA DE FIN'));
      expect(fila.label, contains('Ahora'));
      expect(fila.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantica.dispose();
    });
  });

  group('tamaños: 360×640 y 412×915, sin desborde y con el aviso a la vista', () {
    for (final (nombre, estado) in _estados) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          final cuando =
              '$nombre · ${tamano.width.toInt()}×${tamano.height.toInt()} · '
              'texto ${(escala * 100).toInt()} %';

          testWidgets('reposo y con aviso · $cuando', (tester) async {
            await cargarFuentes205(tester);
            _local.errorAlFinalizar = StateError('disco lleno');
            await _montar(tester, estado: estado, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(_boton);
            await tester.pumpAndSettle();
            await _capturar(
              tester,
              '${nombre.replaceAll(' ', '_')}_${tamano.width.toInt()}_x$escala',
            );

            await _tocarTerminar(tester);
            expect(tester.takeException(), isNull);
            await _capturar(
              tester,
              '${nombre.replaceAll(' ', '_')}_${tamano.width.toInt()}_x${escala}_falla',
            );
            // El aviso queda en pantalla, al menos en parte (a 200 % ocupa casi toda).
            final aviso = tester.getRect(_errorFin);
            expect(aviso.bottom, greaterThan(0));
            expect(aviso.top, lessThan(tamano.height));
          });
        }
      }
    }
  });

  group('la hora de fin: validaciones del cierre que el PR no prueba', () {
    testWidgets('reloj atrasado (inicio en el futuro): dice qué pasa y qué hacer, no cierra', (
      tester,
    ) async {
      _local = LocalDeJornada([jornadaAbiertaDesde(DateTime(2026, 10, 23, 14, 50))]);
      await _montar(tester);

      await _tocarTerminar(tester);

      expect(find.text(JornadaSinCerrar.avisoRelojAtrasado), findsOneWidget);
      expect(_local.unica.estaAbierta, isTrue);
      expect(_alTocar(tester), isNotNull);
      expect(find.text('Terminando…'), findsNothing);
    });

    testWidgets('la hora elegida se vence con la pantalla abierta: pide otra, sin inventarla', (
      tester,
    ) async {
      await _montar(tester);
      await _elegirMinutosAntes(tester, 6); // 14:11
      expect(find.textContaining('14:11'), findsOneWidget);

      // Pasa casi una hora con la pantalla abierta: 14:11 ya está a más de 30 min.
      _reloj = DateTime(2026, 10, 23, 15, 30);
      await tester.pump(const Duration(minutes: 49));
      await tester.pump();

      await _tocarTerminar(tester);

      expect(find.textContaining('Elegí otra hora y volvé a intentar.'), findsOneWidget);
      expect(_local.unica.estaAbierta, isTrue);
      expect(_alTocar(tester), isNotNull);
      // La hora elegida no se tocó en silencio.
      expect(find.textContaining('14:11'), findsOneWidget);
    });

    testWidgets('el reloj avanza con la pantalla abierta: «Ahora» se actualiza y guarda esa hora', (
      tester,
    ) async {
      await _montar(tester);
      expect(find.textContaining('14:41'), findsOneWidget);

      _reloj = DateTime(2026, 10, 23, 14, 42);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(find.textContaining('14:42'), findsOneWidget);

      await _tocarTerminar(tester);

      expect(_local.unica.fin!.isAtSameMomentAs(DateTime(2026, 10, 23, 14, 42)), isTrue);
    });

    testWidgets('lo elegido no se pierde tras una falla: la hora sigue y el reintento la usa', (
      tester,
    ) async {
      _local.errorAlFinalizar = StateError('disco lleno');
      await _montar(tester);
      await _elegirMinutosAntes(tester, 1); // 14:36

      await _tocarTerminar(tester);
      expect(_errorFin, findsOneWidget);
      expect(find.textContaining('14:36'), findsOneWidget);

      _local.errorAlFinalizar = null;
      await _tocarTerminar(tester);

      expect(_local.unica.fin!.isAtSameMomentAs(DateTime(2026, 10, 23, 14, 36)), isTrue);
    });

    testWidgets('falla del guardado y la jornada se relee: el aviso no se va solo', (tester) async {
      _local.errorAlFinalizar = StateError('disco lleno');
      await _montar(tester);
      await _tocarTerminar(tester);

      _reloj = DateTime(2026, 10, 23, 14, 42);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(_errorFin, findsOneWidget);
    });
  });

  group('superposiciones y reentrada', () {
    testWidgets('una entrevista abierta y dos toques seguidos: una sola hoja', (tester) async {
      await _montaje.almacen.guardar(entrevistaDePrueba());
      await _montar(tester);
      await tester.ensureVisible(_boton);

      await tester.tap(_boton);
      await tester.tap(_boton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Terminó la entrevista'), findsOneWidget);
      expect(_local.cierres, 0);
    });

    testWidgets(
      'ir a Configuración y volver con el cierre en vuelo: sigue «Terminando…» y el cierre termina',
      (tester) async {
        final cierre = _local.demoraFinalizar = Completer<void>();
        await _montar(tester, estado: EstadoCuenta.pendienteAsignacion);
        await tester.ensureVisible(_boton);
        await tester.tap(_boton);
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.byKey(const Key('espera_configuracion')));
        await tester.pump(const Duration(seconds: 1));
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Terminando…'), findsOneWidget);

        cierre.complete();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        expect(_local.unica.estaAbierta, isFalse);
        expect(_resumen, findsOneWidget);
      },
    );

    testWidgets(
      'jornada de un día anterior: elegir la hora la cierra y «Volver al inicio» deja la cuenta',
      (tester) async {
        _local = LocalDeJornada([jornadaAbiertaDesde(DateTime(2026, 10, 22, 22))]);
        await _montar(tester);
        await _tocarTerminar(tester);
        expect(find.byKey(const Key('corregir_jornada_mensaje')), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('corregir_jornada_elegir_hora')));
        await tester.tap(find.byKey(const Key('corregir_jornada_elegir_hora')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('hoja_hora_valor')));
        await tester.tap(find.byKey(const Key('hoja_hora_valor')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('hoja_hora_campo')), '22:30');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('hoja_hora_usar_escrita')));
        await tester.tap(find.byKey(const Key('hoja_hora_usar_escrita')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('corregir_jornada_cerrar')));
        await tester.tap(find.byKey(const Key('corregir_jornada_cerrar')));
        await tester.pumpAndSettle();

        expect(_local.unica.estaAbierta, isFalse);
        expect(_local.unica.fin!.isAtSameMomentAs(DateTime(2026, 10, 22, 22, 30)), isTrue);
        expect(_resumen, findsOneWidget);
        await tester.tap(find.text('Volver al inicio'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cuenta_terminar_jornada')), findsNothing);
        expect(find.text('Cuenta suspendida'), findsOneWidget);
      },
    );

    testWidgets(
      '«Volver al inicio» y vuelta a entrar: la sección ya no está y no hay estado viejo',
      (tester) async {
        await _montar(tester);
        await _tocarTerminar(tester);
        await tester.tap(find.text('Volver al inicio'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cuenta_terminar_jornada')), findsNothing);
        expect(find.text('Terminando…'), findsNothing);
        expect(find.textContaining('sigue abierta'), findsNothing);
      },
    );
  });

  group('estados de la vista 18 con la sección a la vista', () {
    testWidgets('18-A02 consultando: «Actualizar» en vuelo no tapa ni apaga «Terminar jornada»', (
      tester,
    ) async {
      await _montar(tester, estado: EstadoCuenta.pendienteAsignacion);
      await tester.ensureVisible(find.byKey(const Key('espera_actualizar')));
      await tester.tap(find.byKey(const Key('espera_actualizar')));
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byKey(const Key('cuenta_terminar_jornada')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('cuenta_terminar_jornada')), findsOneWidget);
      expect(_alTocar(tester), isNotNull);
    });
  });

  group('decisión del orquestador (29/10), P2: error al leer la jornada', () {
    testWidgets(
      'si no se puede leer la jornada: el aviso de «Hoy» con «Reintentar», y al reintentar vuelve',
      (tester) async {
        _local.errorAlLeer = StateError('disco');
        await _montar(tester);

        expect(find.text('No pudimos leer tu jornada.'), findsOneWidget);
        final reintentar = find.text('Reintentar');
        expect(reintentar, findsOneWidget);

        _local.errorAlLeer = null;
        await tester.ensureVisible(reintentar);
        await tester.tap(reintentar);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cuenta_terminar_jornada')), findsOneWidget);
      },
    );
  });

  group('privacidad', () {
    test('la sección no escribe en el log ni expone datos del colportor', () {
      final fuente = File(
        'lib/features/auth/presentation/widgets/terminar_jornada_de_la_cuenta.dart',
      ).readAsStringSync();
      expect(fuente, isNot(contains('print(')));
      expect(fuente, isNot(contains('debugPrint')));
      expect(fuente, isNot(contains('log(')));
    });
  });

  group('captura de la hoja de la hora de fin', () {
    testWidgets('selector abierto en 360×640 y 412×915', (tester) async {
      await cargarFuentes205(tester);
      for (final tamano in _tamanos) {
        await _montar(tester, tamano: tamano);
        await tester.ensureVisible(_filaFin);
        await tester.tap(_filaFin);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capturar(tester, 'hoja_${tamano.width.toInt()}');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
    });
  });
}

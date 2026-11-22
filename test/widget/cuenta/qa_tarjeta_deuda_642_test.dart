// QA de #642 (vista 33A·01/03/04, tarjeta «Deuda con la casa editora» de Mi Cuenta): la línea de
// variación contra la semana pasada y la tarjeta sin lectura (leyendo, sin conexión, falla del
// servidor). Matriz de 10 estados × 360x640 y 412x915 × texto 1,0 y 2,0 con las fuentes reales,
// guías de accesibilidad por estado, lector de pantalla, casos límite y privacidad. Con
// `--dart-define=QA_CAPTURAS=true` deja un PNG por estado en `.dart_tool/qa_capturas/` (no se
// commitean); con `--dart-define=QA_HALLAZGOS=true` corre los tests que documentan un hallazgo.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/deuda_casa_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/deuda_casa_arnes.dart';

const _capturar = bool.fromEnvironment('QA_CAPTURAS');
const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

enum _E {
  bajo('33A·01 baja'),
  subio('33A·01 sube'),
  igual('33A·01 igual'),
  sinDatos('33A·04 sin datos'),
  aFavor('33A·01 a favor'),
  nueva('33A·04 cuenta nueva'),
  leyendo('33A·03 leyendo'),
  sinConexion('sin lectura · sin conexión'),
  falla('sin lectura · falla'),
  guardadaConFalla('lo guardado + falla'),
  montoEnorme('monto enorme');

  const _E(this.artboard);
  final String artboard;
}

Future<RepositorioDeDeudaControlable> _llevarA(
  WidgetTester tester,
  _E e, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  GlobalKey? raiz,
}) async {
  final repo = RepositorioDeDeudaControlable(
    guardada: switch (e) {
      _E.guardadaConFalla => lectura(deuda(total: 18400, haceUnaSemana: 20500)),
      _ => null,
    },
  );
  await montarCuenta(
    tester,
    RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
    tamano: tamano,
    escala: escala,
    boundary: raiz,
    overrides: overridesDeDeuda(repo),
  );
  await tester.pump();
  Future<void> r(DeudaConLaCasa d) async {
    repo.responder(lectura(d));
    await tester.pump();
    await tester.pump();
  }

  Future<void> f(Failure falla) async {
    repo.fallar(falla);
    await tester.pump();
    await tester.pump();
  }

  switch (e) {
    case _E.bajo:
      await r(deuda(total: 18400, haceUnaSemana: 20500));
    case _E.subio:
      await r(deuda(total: 18400, haceUnaSemana: 15000));
    case _E.igual:
      await r(deuda(total: 18400, haceUnaSemana: 18400));
    case _E.sinDatos:
      await r(deuda(total: 18400));
    case _E.aFavor:
      await r(deuda(total: -1200, suma: 0, haceUnaSemana: 500));
    case _E.nueva:
      await r(deuda(total: 0));
    case _E.leyendo:
      break;
    case _E.sinConexion:
      await f(const FailureDeudaSinConexion());
    case _E.falla:
      await f(const FailureDeudaNoDisponible());
    case _E.guardadaConFalla:
      await f(const FailureDeudaSinConexion());
    case _E.montoEnorme:
      await r(deuda(total: 987654321, haceUnaSemana: 123456789));
  }
  return repo;
}

Future<void> _cargarFuentes(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await c.load();
  }
  final raiz = Platform.environment['FLUTTER_ROOT'] ?? '/sdks/flutter';
  final cache = '$raiz/bin/cache';
  final iconos = File('$cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (iconos.existsSync()) {
    final c = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
    await c.load();
  }
});

Future<void> _png(WidgetTester tester, GlobalKey raiz, String nombre) async {
  Directory('.dart_tool/qa_capturas').createSync(recursive: true);
  await tester.runAsync(() async {
    final r = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz));
    final img = await r.toImage();
    final bd = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    File('.dart_tool/qa_capturas/$nombre.png').writeAsBytesSync(Uint8List.view(bd.buffer));
  });
}

void main() {
  const tarjeta = Key('cuenta_deuda');
  const tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

  group('matriz de estados × tamaños × texto (fuentes reales)', () {
    for (final e in _E.values) {
      for (final t in tamanos.entries) {
        for (final esc in const [1.0, 2.0]) {
          testWidgets('${e.artboard} · ${e.name} · ${t.key} · ${esc}x: sin overflow, la tarjeta '
              'entra a lo ancho${_capturar ? ' (y captura)' : ''}', (tester) async {
            await _cargarFuentes(tester);
            final raiz = GlobalKey();
            await _llevarA(tester, e, tamano: t.value, escala: esc, raiz: raiz);
            expect(tester.takeException(), isNull);
            final caja = tester.getRect(find.byKey(tarjeta));
            expect(caja.left, greaterThanOrEqualTo(0));
            expect(caja.right, lessThanOrEqualTo(t.value.width));
            expect(caja.height, greaterThanOrEqualTo(72));
            if (_capturar) {
              await _png(tester, raiz, '642_tarjeta_${e.name}_${t.key}_x${esc.toInt()}');
            }
          });
        }
      }
    }
  });

  group('guías de accesibilidad por estado', () {
    for (final e in _E.values) {
      for (final t in tamanos.entries) {
        testWidgets('${e.artboard} · ${e.name} · ${t.key}: toques, etiquetas y contraste', (
          tester,
        ) async {
          final h = tester.ensureSemantics();
          await _llevarA(tester, e, tamano: t.value);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          h.dispose();
        });
      }
      testWidgets('${e.artboard} · ${e.name} · 360x640 al 200 %: toques y etiquetas', (
        tester,
      ) async {
        final h = tester.ensureSemantics();
        await _llevarA(tester, e, tamano: const Size(360, 640), escala: 2);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      });
    }
  });

  group('lector de pantalla', () {
    final esperado = {
      _E.leyendo: 'Deuda con la casa editora. Cargando tu deuda con la casa editora',
      _E.sinConexion:
          'Deuda con la casa editora. Necesitás conexión para ver tu deuda con la casa editora.',
      _E.falla: 'Deuda con la casa editora. No pudimos traer tu deuda con la casa editora.',
      _E.sinDatos: r'Deuda con la casa editora, $ 18.400. Sin datos de la semana anterior',
      _E.igual: r'Deuda con la casa editora, $ 18.400. Igual que la semana pasada',
      _E.subio: r'Deuda con la casa editora, $ 18.400. Subió $ 3.400 contra la semana pasada',
      _E.aFavor:
          r'Deuda con la casa editora, a favor $ 1.200. Bajó $ 1.700 contra la semana pasada',
    };
    for (final entrada in esperado.entries) {
      testWidgets('${entrada.key.artboard}: se lee como un botón con su rótulo y la línea que lo '
          'explica', (tester) async {
        final h = tester.ensureSemantics();
        await _llevarA(tester, entrada.key);
        final s = tester.getSemantics(find.byKey(tarjeta));
        expect(s.label, entrada.value);
        expect(s.flagsCollection.isButton, isTrue);
        expect(s.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        h.dispose();
      });
    }

    // skip: QA #642 — la tarjeta pasa de «Cargando…» a «No pudimos traer tu deuda…» sin región viva:
    // el lector no anuncia el cambio (mismo hueco que el aviso de 33B en #441).
    testWidgets('el cambio de «leyendo» a una falla se anuncia (región viva)', (tester) async {
      final h = tester.ensureSemantics();
      await _llevarA(tester, _E.falla);
      final nodo = tester.getSemantics(find.byKey(tarjeta));
      var viva = nodo.flagsCollection.isLiveRegion;
      nodo.visitChildren((hijo) {
        viva = viva || hijo.flagsCollection.isLiveRegion;
        return true;
      });
      expect(viva, isTrue);
      h.dispose();
    }, skip: !_hallazgos);
  });

  group('casos límite', () {
    testWidgets('sin conexión y sin nada guardado: tocar la tarjeta abre el detalle (la salida)', (
      tester,
    ) async {
      final repo = await _llevarA(tester, _E.sinConexion);
      final antes = repo.lecturas;
      await tester.tap(find.byKey(tarjeta));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('Deuda con la casa editora'), findsWidgets);
      expect(repo.lecturas, greaterThanOrEqualTo(antes));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'la tarjeta con lo guardado y una falla sigue mostrando la cifra, no la línea gris',
      (tester) async {
        await _llevarA(tester, _E.guardadaConFalla);
        expect(find.byKey(const Key('cuenta_deuda_monto')), findsOneWidget);
        expect(find.byKey(const Key('cuenta_deuda_sin_lectura')), findsNothing);
        expect(find.byKey(const Key('cuenta_deuda_cargando')), findsNothing);
      },
    );

    testWidgets('monto enorme: el total y la variación se leen enteros (sin elipsis)', (
      tester,
    ) async {
      await _cargarFuentes(tester);
      await _llevarA(tester, _E.montoEnorme, tamano: const Size(360, 640), escala: 2);
      expect(tester.takeException(), isNull);
      final monto = tester.widget<Text>(find.byKey(const Key('cuenta_deuda_monto')));
      expect(monto.overflow, isNull);
      expect(monto.maxLines, isNull);
      expect(monto.data, r'$ 987.654.321');
      final linea = tester.widget<Text>(find.byKey(const Key('cuenta_deuda_variacion')));
      expect(linea.data, r'▲ $ 864.197.532 contra la semana pasada');
    });

    testWidgets('reentrar a Mi Cuenta tras una falla vuelve a mostrar «leyendo» y no deja la línea '
        'vieja', (tester) async {
      final repo = await _llevarA(tester, _E.falla);
      expect(find.byKey(const Key('cuenta_deuda_sin_lectura')), findsOneWidget);
      await tester.tap(find.byKey(tarjeta));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      // Tocar la tarjeta pidió de nuevo; el detalle espera y, si falla otra vez, ofrece «Reintentar».
      expect(repo.pendientes, 1);
      repo.fallar();
      await tester.pump();
      await tester.pump();
      expect(find.text('Reintentar'), findsOneWidget, reason: 'el detalle ofrece la salida');
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(repo.pendientes, 1);
      repo.responder(lectura(deuda(total: 500, haceUnaSemana: 900)));
      await tester.pump();
      await tester.pump();
      await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(const Key('cuenta_deuda_sin_lectura')), findsNothing);
      expect(find.byKey(const Key('cuenta_deuda_monto')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('cuenta_deuda_monto'))).data, r'$ 500');
      expect(
        tester.widget<Text>(find.byKey(const Key('cuenta_deuda_variacion'))).data,
        r'▼ $ 400 contra la semana pasada',
      );
    });

    testWidgets('el color de la variación de una deuda que subió no es verde (no celebra una mala '
        'noticia)', (tester) async {
      await _llevarA(tester, _E.subio);
      final c = tester.widget<Text>(find.byKey(const Key('cuenta_deuda_variacion'))).style!.color;
      expect(c, isNot(const Color(0xFF1F6E3A)));
    });
  });

  group('privacidad', () {
    test('toString de la deuda y del estado no vuelca montos ni pedidos (stringify apagado)', () {
      final d = deuda(total: 18400, haceUnaSemana: 20500);
      expect(d.toString(), isNot(contains('18400')));
      expect(d.toString(), isNot(contains('2050000')));
      expect(const EstadoDeLaDeuda().toString(), isNot(contains('actualizando')));
    });
  });
}

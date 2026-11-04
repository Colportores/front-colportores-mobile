// QA de «Depositado» en «Mi plata» (vista 33C, HU-CTA-003, #431): lo que los tests del implementador y el
// QA de #172 no recorren. Las cuatro guías de accesibilidad en cada estado de «Depositado» (con el
// texto al 200 %), los textos que fijó la decisión del 04/11 (P1), el orden y la suma de la lista, los
// casos límite (la bajada que desaparece, la falla a mitad con «Reintentar», 600 depósitos, las tres
// categorías abiertas a 360×640 al 200 %), Mi Cuenta con sus tres tarjetas tocables y las capturas.
//
// Los tests que documentan un hallazgo corren con `--dart-define=QA_HALLAZGOS=true`; las capturas, con
// `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`, gitignored: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/detalle_de_mi_plata.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/mi_plata_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/cuenta/presentation/widgets/piezas_mi_plata.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';

const _raiz = Key('qa_raiz_captura_431');

/// Los tests que documentan un hallazgo solo corren con `--dart-define=QA_HALLAZGOS=true`.
const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true`.
const _sacarCapturas = bool.fromEnvironment('QA_CAPTURAS');

const _chico = Size(360, 640);
const _grande = Size(412, 915);
const _tamanos = {'360x640': _chico, '412x915': _grande};

/// Carga las fuentes reales; sin ellas las capturas salen con cajas.
Future<void> _cargarFuentes() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
  final flutter = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final iconos = File(
    '${flutter.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconos.existsSync()) {
    final cargador = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
    await cargador.load();
  }
}

/// Monta «Mi plata» sola (con el árbol de captura alrededor) a [tamano] y con el texto a [escala].
Future<void> _montar(
  WidgetTester tester,
  RepositorioDeDetalleControlable repo, {
  CategoriaDeMiPlata abierta = CategoriaDeMiPlata.depositado,
  Size tamano = _chico,
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [detalleDeMiPlataRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: _raiz, child: child),
        ),
        home: MiPlataPage(colportorId: 'col-1', abierta: abierta),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/431_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Un detalle con [depositado] y lo demás del canvas.
DetalleDeMiPlata _con(DepositadoEnMiPlata? depositado) => DetalleDeMiPlata(
  depositado: depositado,
  enManoCentavos: detalleDelCanvas.enManoCentavos,
  enMano: detalleDelCanvas.enMano,
  porCobrarCentavos: detalleDelCanvas.porCobrarCentavos,
  porCobrar: detalleDelCanvas.porCobrar,
);

/// $ 26.900 validados en tres depósitos y $ 2.300 que esperan: el caso de la decisión P1.
final _conAparte = DepositadoEnMiPlata(
  validados: depositadoDelCanvas.validados,
  porValidar: [depositoDe(1800, 22, validado: false), depositoDe(500, 23, validado: false)],
);

final _soloPorValidar = DepositadoEnMiPlata(
  validados: const [],
  porValidar: [depositoDe(2300, 22, validado: false, destino: DestinoDeDeposito.retiroCoordinador)],
);

const _sinDepositos = DepositadoEnMiPlata(validados: [], porValidar: []);

/// Montos de 11 cifras, el caso límite de ancho.
final _montosGrandes = DepositadoEnMiPlata(
  validados: [depositoDe(99999999999, 12)],
  porValidar: [depositoDe(88888888888, 22, validado: false)],
);

/// Cada estado de «Depositado» abierto con lo que hace falta para llegar a él.
final _estados = <String, DetalleDeMiPlata>{
  'depositado_con_aparte': _con(_conAparte),
  'depositado_solo_validados': _con(depositadoDelCanvas),
  'depositado_solo_por_validar': _con(_soloPorValidar),
  'depositado_sin_depositos': _con(_sinDepositos),
  'depositado_montos_de_11_cifras': _con(_montosGrandes),
};

/// Toca la cabecera de [c] como lo hace la persona: bajando por la lista hasta verla.
Future<void> _tocarCabecera(WidgetTester tester, CategoriaDeMiPlata c) async {
  final cabecera = find.byKey(Key('mi_plata_categoria_${c.name}'));
  await tester.scrollUntilVisible(
    cabecera,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
  await tester.tap(cabecera);
  await tester.pumpAndSettle();
}

Finder _fila(String tipo, int i) => find.byKey(Key('mi_plata_fila_${tipo}_$i'));

void main() {
  group('accesibilidad: las cuatro guías en cada estado de «Depositado»', () {
    for (final tam in _tamanos.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in _estados.entries) {
          testWidgets('${estado.key} a ${tam.key}, texto $escala', (tester) async {
            final handle = tester.ensureSemantics();
            await _montar(
              tester,
              RepositorioDeDetalleControlable(inicial: estado.value),
              tamano: tam.value,
              escala: escala,
            );

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            expect(tester.takeException(), isNull);
            handle.dispose();
          });
        }
      }
    }

    for (final tam in _tamanos.entries) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('las tres categorías abiertas a ${tam.key}, texto $escala', (tester) async {
          final handle = tester.ensureSemantics();
          await _montar(
            tester,
            RepositorioDeDetalleControlable(inicial: _con(_conAparte)),
            tamano: tam.value,
            escala: escala,
          );
          // Abrir las otras dos con los toques del usuario (cada una trae su cabecera a la vista).
          for (final c in [CategoriaDeMiPlata.enMano, CategoriaDeMiPlata.porCobrar]) {
            await _tocarCabecera(tester, c);
          }
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }
  });

  group('los textos de «Depositado» abierto (decisión del 04/11, P1)', () {
    testWidgets(
      'el aparte dice «Por validar» con \$ 2.300 y qué esperar, y sus filas van en gris',
      (tester) async {
        await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(_conAparte)));

        expect(find.text('Por validar'), findsOneWidget);
        expect(find.text(r'$ 2.300'), findsOneWidget);
        expect(_fila('porValidar', 0), findsOneWidget);
        expect(_fila('porValidar', 1), findsOneWidget);
        expect(_fila('porValidar', 2), findsNothing);
        final monto = tester.widget<Text>(
          find.descendant(of: _fila('porValidar', 0), matching: find.textContaining(r'$ 1.800')),
        );
        expect(monto.style?.color, ColoresCuentaParaQa.gris);
      },
    );

    testWidgets('cada fila dice para qué era, dónde y cuándo: «Casa editora · Banco · 12/10»', (
      tester,
    ) async {
      await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(depositadoDelCanvas)));

      expect(find.text('Casa editora · Banco · 12/10'), findsOneWidget);
      expect(find.text('Casa editora · Oficina · 15/10'), findsOneWidget);
      expect(find.text('Alquiler · Banco · 19/10'), findsOneWidget);
    });

    testWidgets('el retiro del coordinador se llama «Retiro»', (tester) async {
      await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(_soloPorValidar)));

      expect(find.text('Casa editora · Retiro · 22/10'), findsOneWidget);
    });

    testWidgets('sin ningún depósito dice «Todavía no registraste ningún depósito.»', (
      tester,
    ) async {
      await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(_sinDepositos)));

      expect(find.text('Todavía no registraste ningún depósito.'), findsOneWidget);
      expect(find.text('Por validar'), findsNothing);
    });

    // QA #431: la decisión del 04/11 (P1) fija el texto «Suman a Depositado cuando tu coordinador los
    // valide.» «(sin comillas anidadas)»; el código dice «Suman a «Depositado» cuando…».
    testWidgets(
      'el aviso del aparte no lleva comillas anidadas: «Suman a Depositado cuando tu coordinador los valide.»',
      (tester) async {
        await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(_conAparte)));

        expect(find.text('Suman a Depositado cuando tu coordinador los valide.'), findsOneWidget);
      },
    );

    // QA #431: la decisión P1 manda sacar «Para confirmar» de `TextosMiPlata`.
    test('TextosMiPlata ya no dice «Para confirmar» (P1 del 04/11)', () {
      final fuente = File('lib/features/cuenta/presentation/textos_cuenta.dart').readAsStringSync();
      final miPlata = fuente.substring(
        fuente.indexOf('abstract final class TextosMiPlata'),
        fuente.indexOf('abstract final class FormatoCuenta'),
      );
      expect(miPlata, isNot(contains('Para confirmar')));
    }, skip: !_hallazgos);
  });

  group('el orden y la suma de la lista', () {
    testWidgets('los validados van primero, después el aparte con sus filas', (tester) async {
      await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(_conAparte)));

      final ultimoValidado = tester.getTopLeft(_fila('depositado', 2)).dy;
      final aparte = tester.getTopLeft(find.byKey(const Key('mi_plata_por_validar'))).dy;
      final primeroPorValidar = tester.getTopLeft(_fila('porValidar', 0)).dy;
      expect(aparte, greaterThan(ultimoValidado));
      expect(primeroPorValidar, greaterThan(aparte));
      // Lo más viejo primero dentro de cada lista.
      expect(tester.getTopLeft(_fila('depositado', 0)).dy, lessThan(ultimoValidado));
      expect(tester.getTopLeft(_fila('porValidar', 1)).dy, greaterThan(primeroPorValidar));
    });

    testWidgets('la cifra de «Depositado» suma solo lo validado, no lo que espera', (tester) async {
      await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(_conAparte)));

      // 10.000 + 9.000 + 7.900 = 26.900; los 2.300 del aparte no entran.
      expect(find.text('\$ 26.900  ▴'), findsOneWidget);
      expect(find.text('\$ 29.200  ▴'), findsNothing);
    });

    testWidgets('con solo lo que espera, la cifra es cero y el aparte sigue a la vista', (
      tester,
    ) async {
      await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(_soloPorValidar)));

      expect(find.text('\$ 0  ▴'), findsOneWidget);
      expect(find.byKey(const Key('mi_plata_por_validar')), findsOneWidget);
      expect(find.byKey(const Key('mi_plata_vacio_depositado')), findsNothing);
    });

    testWidgets('el lector lee la cabecera como botón desplegado y el aparte como encabezado', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(_conAparte)));

      expect(
        tester.getSemantics(find.byKey(const Key('mi_plata_categoria_depositado'))),
        isSemantics(
          label: r'Depositado, $ 26.900, desplegado',
          isButton: true,
          isExpanded: true,
          hasTapAction: true,
        ),
      );
      // El aparte se lee de una vez, como encabezado, con el aviso incluido.
      final aparte = find.bySemanticsLabel(RegExp(r'^Por validar, \$ 2\.300\. Suman a'));
      expect(aparte, findsOneWidget);
      expect(tester.getSemantics(aparte), isSemantics(isHeader: true));
      handle.dispose();
    });
  });

  group('casos límite de «Depositado»', () {
    testWidgets('toca la cabecera dos veces: se pliega y se vuelve a abrir, sin quedar trabada', (
      tester,
    ) async {
      await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(_conAparte)));
      final cabecera = find.byKey(const Key('mi_plata_categoria_depositado'));

      await tester.tap(cabecera);
      await tester.pumpAndSettle();
      expect(_fila('depositado', 0), findsNothing);
      expect(find.byKey(const Key('mi_plata_por_validar')), findsNothing);

      await tester.tap(cabecera);
      await tester.pumpAndSettle();
      expect(_fila('depositado', 0), findsOneWidget);
      expect(find.byKey(const Key('mi_plata_por_validar')), findsOneWidget);
    });

    testWidgets(
      'si el teléfono pierde la bajada, «Depositado» desaparece y al volver sigue abierto',
      (tester) async {
        final repo = RepositorioDeDetalleControlable(inicial: _con(_conAparte));
        await _montar(tester, repo);

        repo.emitir(_con(null));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mi_plata_categoria_depositado')), findsNothing);
        expect(find.byKey(const Key('mi_plata_categoria_enMano')), findsOneWidget);
        expect(tester.takeException(), isNull);

        repo.emitir(_con(_conAparte));
        await tester.pumpAndSettle();
        expect(_fila('depositado', 0), findsOneWidget);
      },
    );

    testWidgets(
      'la falla con «Depositado» abierto dice qué pasó, y «Reintentar» lo trae de vuelta abierto',
      (tester) async {
        final repo = RepositorioDeDetalleControlable(inicial: _con(_conAparte));
        await _montar(tester, repo);

        repo.fallar();
        await tester.pumpAndSettle();
        expect(find.text('Reintentar'), findsOneWidget);
        expect(_fila('depositado', 0), findsNothing);

        repo.inicial = _con(_conAparte);
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(find.text('Reintentar'), findsNothing);
        expect(_fila('depositado', 0), findsOneWidget);
        expect(find.byKey(const Key('mi_plata_por_validar')), findsOneWidget);
        expect(repo.suscripciones, 2);
      },
    );

    testWidgets('«Reintentar» que vuelve a fallar deja el botón disponible otra vez', (
      tester,
    ) async {
      final repo = RepositorioDeDetalleControlable()..fallaAlSuscribir = true;
      await _montar(tester, repo);
      expect(find.text('Reintentar'), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(find.text('Reintentar'), findsOneWidget, reason: 'intento ${i + 2}');
      }
      expect(repo.suscripciones, 4);
    });

    testWidgets('la validación que baja mueve el depósito del aparte a lo validado sin recargar', (
      tester,
    ) async {
      final repo = RepositorioDeDetalleControlable(inicial: _con(_conAparte));
      await _montar(tester, repo);
      expect(find.text('\$ 26.900  ▴'), findsOneWidget);

      repo.emitir(
        _con(
          DepositadoEnMiPlata(
            validados: [...depositadoDelCanvas.validados, depositoDe(1800, 22)],
            porValidar: [depositoDe(500, 23, validado: false)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('\$ 28.700  ▴'), findsOneWidget);
      expect(_fila('depositado', 3), findsOneWidget);
      expect(_fila('porValidar', 0), findsOneWidget);
      expect(_fila('porValidar', 1), findsNothing);
      expect(find.text(r'$ 500'), findsNWidgets(2)); // el monto de la fila y el del encabezado
    });

    testWidgets('cuando el último depósito del aparte se valida, el aparte desaparece', (
      tester,
    ) async {
      final repo = RepositorioDeDetalleControlable(inicial: _con(_soloPorValidar));
      await _montar(tester, repo);
      expect(find.byKey(const Key('mi_plata_por_validar')), findsOneWidget);

      repo.emitir(
        _con(DepositadoEnMiPlata(validados: [depositoDe(2300, 22)], porValidar: const [])),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mi_plata_por_validar')), findsNothing);
      expect(find.text('\$ 2.300  ▴'), findsOneWidget);
    });

    testWidgets('600 depósitos con el aparte al final: se arma de a poco y el aparte se alcanza', (
      tester,
    ) async {
      final muchos = DepositadoEnMiPlata(
        validados: [for (var i = 0; i < 500; i++) depositoDe(100 + i, 1 + i % 27)],
        porValidar: [for (var i = 0; i < 100; i++) depositoDe(50 + i, 28, validado: false)],
      );
      await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(muchos)));

      expect(find.byKey(const Key('mi_plata_por_validar')), findsNothing); // perezoso
      await tester.scrollUntilVisible(
        find.byKey(const Key('mi_plata_por_validar')),
        800,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 400,
      );
      expect(find.byKey(const Key('mi_plata_por_validar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 360×640 con el texto al 200 % se abren y cierran las tres y no hay overflow', (
      tester,
    ) async {
      await _montar(tester, RepositorioDeDetalleControlable(inicial: _con(_conAparte)), escala: 2);
      for (final c in CategoriaDeMiPlata.values) {
        await _tocarCabecera(tester, c);
        expect(tester.takeException(), isNull, reason: 'tocar ${c.name}');
      }
    });

    testWidgets('el botón «Volver» existe y mide 48 dp en cada estado de «Depositado»', (
      tester,
    ) async {
      for (final estado in _estados.values) {
        await _montar(tester, RepositorioDeDetalleControlable(inicial: estado));
        expect(find.byKey(const Key('mi_plata_volver')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const Key('mi_plata_volver'))).shortestSide,
          greaterThanOrEqualTo(48),
        );
      }
    });
  });

  group('Mi Cuenta con sus tres tarjetas tocables', () {
    for (final tam in _tamanos.entries) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('las guías a ${tam.key}, texto $escala', (tester) async {
          final handle = tester.ensureSemantics();
          await montarCuenta(
            tester,
            RepositorioDeCuentaControlable(inicial: resumenConDepositado),
            tamano: tam.value,
            escala: escala,
          );

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          expect(tester.takeException(), isNull);
          handle.dispose();
        });
      }
    }

    testWidgets(
      'la tarjeta «Depositado» se lee como botón y abre Mi plata con Depositado abierto',
      (tester) async {
        final handle = tester.ensureSemantics();
        final detalle = RepositorioDeDetalleControlable(inicial: _con(_conAparte));
        await montarCuentaConDetalle(
          tester,
          RepositorioDeCuentaControlable(inicial: resumenConDepositado),
          detalle,
        );

        expect(
          tester.getSemantics(find.byKey(const Key('cuenta_depositado'))),
          isSemantics(isButton: true, hasTapAction: true),
        );
        await tester.tap(find.byKey(const Key('cuenta_depositado')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('mi_plata_lista')), findsOneWidget);
        expect(_fila('depositado', 0), findsOneWidget);
        expect(find.byKey(const Key('mi_plata_por_validar')), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets(
      'dos toques seguidos en «Depositado» abren una sola Mi plata; volver y reabrir anda',
      (tester) async {
        final detalle = RepositorioDeDetalleControlable(inicial: _con(_conAparte));
        await montarCuentaConDetalle(
          tester,
          RepositorioDeCuentaControlable(inicial: resumenConDepositado),
          detalle,
        );

        await tester.tap(find.byKey(const Key('cuenta_depositado')));
        await tester.tap(find.byKey(const Key('cuenta_depositado')), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mi_plata_lista')), findsOneWidget);

        await tester.tap(find.byKey(const Key('mi_plata_volver')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mi_plata_lista')), findsNothing);

        await tester.tap(find.byKey(const Key('cuenta_depositado')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mi_plata_lista')), findsOneWidget);
        // Una sola pantalla encima: volver una vez deja Mi Cuenta.
        await tester.tap(find.byKey(const Key('mi_plata_volver')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cuenta_depositado')), findsOneWidget);
        expect(find.byKey(const Key('mi_plata_lista')), findsNothing);
      },
    );

    testWidgets(
      'sin la bajada del servidor no hay tarjeta «Depositado» ni entrada a esa categoría',
      (tester) async {
        await montarCuentaConDetalle(
          tester,
          RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
          RepositorioDeDetalleControlable(inicial: _con(null)),
        );

        expect(find.byKey(const Key('cuenta_depositado')), findsNothing);
        await tester.tap(find.byKey(const Key('cuenta_enMano')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mi_plata_categoria_depositado')), findsNothing);
      },
    );
  });

  group('capturas de cada estado (a .dart_tool/qa_capturas/)', skip: !_sacarCapturas, () {
    setUpAll(_cargarFuentes);

    for (final tam in _tamanos.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in _estados.entries) {
          testWidgets('${estado.key} ${tam.key} x$escala', (tester) async {
            await _montar(
              tester,
              RepositorioDeDetalleControlable(inicial: estado.value),
              tamano: tam.value,
              escala: escala,
            );
            await _capturar(tester, '${estado.key}_${tam.key}_x$escala');
          });
        }
        testWidgets('todas_abiertas ${tam.key} x$escala', (tester) async {
          await _montar(
            tester,
            RepositorioDeDetalleControlable(inicial: _con(_conAparte)),
            tamano: tam.value,
            escala: escala,
          );
          for (final c in [CategoriaDeMiPlata.enMano, CategoriaDeMiPlata.porCobrar]) {
            await _tocarCabecera(tester, c);
          }
          await tester.drag(find.byKey(const Key('mi_plata_lista')), const Offset(0, 6000));
          await tester.pumpAndSettle();
          await _capturar(tester, 'todas_abiertas_${tam.key}_x$escala');
        });
        testWidgets('mi_cuenta_con_depositado ${tam.key} x$escala', (tester) async {
          await montarCuenta(
            tester,
            RepositorioDeCuentaControlable(inicial: resumenConDepositado),
            tamano: tam.value,
            escala: escala,
            boundary: _raiz,
          );
          await _capturar(tester, 'mi_cuenta_${tam.key}_x$escala');
        });
      }
    }
  });
}

/// El gris de las filas apagadas (el mismo `ColoresCuenta.gris` del tema de Mi Cuenta).
abstract final class ColoresCuentaParaQa {
  static const gris = Color(0xFF5B6B82);
}

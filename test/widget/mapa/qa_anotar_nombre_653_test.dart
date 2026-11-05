// QA de #653 (HU-UBI-008, vista 39): anotar el nombre de la persona de forma rápida y opcional.
// Lo que el implementador no cubrió: las cuatro guías de accesibilidad con «Todavía no sé con quién»
// a la vista en R·04 (en sus estados: base, con el aviso de «falta el nombre» y con el nombre pegado
// larguísimo) y en la pestaña Personas vacía (C·02), a 360×640 y 412×915 con texto 1.0 y 2.0; que la
// elección no filtre el nombre ni los ids por `toString`; los bordes de la entrada (solo espacios,
// texto pegado enorme, emoji); y que la lista (C·07) no ofrezca «Todavía no sé».
// Capturas (no se commitean): `--dart-define=QA_CAPTURAS=true` las deja en `.dart_tool/qa_capturas/`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/eleccion_de_entrevista.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_de_la_entrevista.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;
import '../../helpers/persona_falsos.dart';
import 'hoja_con_quien_arnes.dart';
import 'personas_arnes.dart';

const _raiz = Key('qa_raiz_captura_653');
const _sacarCapturas = bool.fromEnvironment('QA_CAPTURAS');
const _todaviaNoSe = 'Todavía no sé con quién';

const _tamanos = [Size(360, 640), Size(412, 915)];
const _escalas = [1.0, 2.0];

Finder get _sinNombre => find.byKey(ClavesConQuien.todaviaNoSe);
Finder get _empezar => find.widgetWithText(FilledButton, 'Empezar entrevista');

Future<void> _cargarFuentes() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/653_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// R·04 (casa sin personas) o, con [personas], C·07, abierto desde un botón, con [escala] y [tamano].
Future<ResultadoConQuien> _abrirConQuien(
  WidgetTester tester, {
  required Size tamano,
  double escala = 1,
  int personas = 0,
}) async {
  final resultado = ResultadoConQuien();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personaRepositoryProvider.overrideWithValue(
          PersonaRepositorioFalso()..sembrar(personasDeLaCasa(personas)),
        ),
        espacioRepositoryProvider.overrideWithValue(
          EspacioRepositorioParaPersonas(contextoActivo()),
        ),
        saldosDePersonasProvider.overrideWithValue(SaldosFalsos(const {})),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        navigatorObservers: [resultado.rutas],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: _raiz, child: child),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final e = await mostrarHojaConQuien(
                    context,
                    espacioId: 'esp-1',
                    colportorId: 'col-1',
                  );
                  resultado
                    ..eleccion = e
                    ..cierres += 1;
                },
                child: const Text('abrir paso'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await abrirPaso(tester);
  return resultado;
}

/// La hoja de la casa recién creada (C·02 sin personas).
Future<void> _abrirHojaVacia(
  WidgetTester tester, {
  required Size tamano,
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overrides = <Override>[
    ...overridesHojaCasa(
      lectura: (_) => Stream.value(const ContextoDeLaCasa(espacioId: 'esp-1', personas: [])),
      registrarVisita: (_) {},
    ),
    personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
    espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(contextoActivo())),
  ];
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: _raiz, child: child),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: itemDeLaHoja(),
              ahora: ahoraLista,
              alCerrar: () {},
              arriba: true,
              colportorId: 'col-1',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

Future<void> _verTodo(WidgetTester tester) async {
  // La guía de toque mide lo que el teléfono ve: el desplazable se deja con el botón nuevo a la vista.
  await tester.ensureVisible(_sinNombre);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    if (_sacarCapturas) await _cargarFuentes();
  });

  group('R·04 · las cuatro guías con «Todavía no sé con quién» a la vista', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        final marca = '${tamano.width.toInt()}x${tamano.height.toInt()} · texto $escala';

        testWidgets('base · $marca', (tester) async {
          await _abrirConQuien(tester, tamano: tamano, escala: escala);
          await _verTodo(tester);

          expect(tester.takeException(), isNull);
          expect(find.text(_todaviaNoSe), findsOneWidget);
          await _guias(tester);
        });

        testWidgets('con «Escribí al menos el nombre.» a la vista · $marca', (tester) async {
          await _abrirConQuien(tester, tamano: tamano, escala: escala);
          await tester.ensureVisible(_empezar);
          await tester.pump();
          await tester.tap(_empezar);
          await asentar(tester);
          await _verTodo(tester);

          expect(tester.takeException(), isNull);
          expect(find.text('Escribí al menos el nombre.'), findsWidgets);
          await _guias(tester);
        });
      }
    }
  });

  group('C·02 · la pestaña Personas vacía, con la línea «para después»', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        testWidgets('${tamano.width.toInt()}x${tamano.height.toInt()} · texto $escala', (
          tester,
        ) async {
          await _abrirHojaVacia(tester, tamano: tamano, escala: escala);
          await tester.ensureVisible(find.byKey(ClavesHojaCasa.agregarPersona));
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byKey(ClavesHojaCasa.sinPersonasParaDespues), findsOneWidget);
          await _guias(tester);
        });
      }
    }
  });

  group('privacidad', () {
    test('la elección de la entrevista no vuelca los ids por toString', () {
      const persona = PersonaDeLaEntrevista(
        personaId: 'per-secreta-1',
        espacioPersonaId: 'ep-secreto-1',
      );

      expect('${const EntrevistaConPersona(persona)}', isNot(contains('secret')));
      expect('${const EntrevistaSinPersona()}', isNot(contains('secret')));
    });
  });

  group('bordes de la entrada en R·04', () {
    testWidgets('solo espacios: «Empezar entrevista» dice qué falta, no guarda y «Todavía no sé» '
        'sigue siendo una salida', (tester) async {
      final r = await _abrirConQuien(tester, tamano: const Size(390, 844));
      await tester.enterText(find.byType(TextField).first, '     ');
      await tester.pump();
      await tester.ensureVisible(_empezar);
      await tester.tap(_empezar);
      await asentar(tester);

      expect(r.cierres, 0);
      expect(find.text('Escribí al menos el nombre.'), findsWidgets);

      await tester.ensureVisible(_sinNombre);
      await tester.tap(_sinNombre);
      await asentar(tester);

      expect(r.sinPersona, isTrue);
      expect(r.cierres, 1);
    });

    testWidgets('texto pegado enorme: el campo lo corta en el límite y nada desborda', (
      tester,
    ) async {
      await _abrirConQuien(tester, tamano: const Size(360, 640), escala: 2);
      final campo = find.byType(TextField).first;
      await tester.enterText(campo, 'Ñ' * 500);
      await tester.pump();

      final texto = tester.widget<TextField>(campo).controller!.text;
      expect(texto.length, AltaPersonaPage.largoNombre);
      expect(tester.takeException(), isNull);
    });

    testWidgets('emoji y caracteres especiales en el nombre no rompen la hoja ni el botón nuevo', (
      tester,
    ) async {
      final r = await _abrirConQuien(tester, tamano: const Size(390, 844));
      await tester.enterText(find.byType(TextField).first, '😀😀 <b>&"\'');
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_sinNombre);
      await tester.tap(_sinNombre);
      await asentar(tester);
      expect(r.sinPersona, isTrue);
    });
  });

  group('C·07 · con varias personas no se ofrece «Todavía no sé con quién»', () {
    testWidgets('dos personas: la lista (sin cambios) no tiene el botón nuevo', (tester) async {
      await _abrirConQuien(tester, tamano: const Size(390, 844), personas: 2);

      expect(_sinNombre, findsNothing);
      expect(find.text('+ Alguien nuevo'), findsOneWidget);
    });
  });

  group('capturas (a .dart_tool/qa_capturas/)', skip: !_sacarCapturas, () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        final marca = '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';

        testWidgets('R04 $marca', (tester) async {
          await _abrirConQuien(tester, tamano: tamano, escala: escala);
          await _capturar(tester, 'R04_$marca');
          await _verTodo(tester);
          await _capturar(tester, 'R04_abajo_$marca');
        });

        testWidgets('C02 vacía $marca', (tester) async {
          await _abrirHojaVacia(tester, tamano: tamano, escala: escala);
          await _capturar(tester, 'C02_vacia_$marca');
        });
      }
    }

    testWidgets('R04 con el teclado y el aviso de falta el nombre (360x640 x2.0)', (tester) async {
      await _abrirConQuien(tester, tamano: const Size(360, 640), escala: 2);
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pump();
      await tester.ensureVisible(_empezar);
      await tester.tap(_empezar);
      await asentar(tester);
      await _capturar(tester, 'R04_teclado_aviso_360x640_x2.0');
      addTearDown(() => tester.view.resetViewInsets());
    });
  });
}

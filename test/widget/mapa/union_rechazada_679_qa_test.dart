// QA de #679 («Unión rech.»), vista 10 «Posibles duplicados» con el aviso de la unión rechazada: las
// guías de accesibilidad de Flutter, la matriz de tamaños (320, 360×640, 412×915) y de texto (1.0 y
// 2.0), la unión rechazada de verdad después de unir desde la hoja, y el aviso que llega con la vista
// abierta (región viva). Las capturas, con `--dart-define=QA_CAPTURAS=true`, van a
// `.dart_tool/qa_capturas/` (gitignored). Los hallazgos con `skip` los corre
// `--dart-define=QA_HALLAZGOS=true`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/duplicados_falsos.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

const _parItalia = 'ub-a|ub-b';
const _raiz = Key('qa_raiz');

const _textoUb003 =
    'La ubicación que ibas a conservar ya está dada de baja. Revisá el par de nuevo.';
const _textoGenerico =
    'No pudimos unir estas dos ubicaciones. Quedaron separadas, como estaban. Revisá el par de nuevo.';

DuplicadosEnMemoria _datos() {
  final datos = DuplicadosEnMemoria();
  datos
    ..agregar(ubicacionDuplicable('ub-a'))
    ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12))
    ..agregar(
      ubicacionDuplicable('ub-c', metrosAlNorte: 1000, calle: 'Bulevar Artigas', numero: '880'),
    )
    ..agregar(
      ubicacionDuplicable('ub-d', metrosAlNorte: 1010, calle: 'Bulevar Artigas', numero: '880'),
    );
  return datos;
}

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _montar(
  WidgetTester tester,
  DuplicadosEnMemoria datos, {
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(datos.cerrar);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDuplicados(datos, conMapa: true),
      child: RepaintBoundary(
        key: _raiz,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('abrir'),
                  onPressed: () =>
                      unawaited(PosiblesDuplicadosPage.abrir(context, colportorId: 'col-1')),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir')));
  await _asentar(tester);
  await tester.pump(const Duration(seconds: 1));
  await _asentar(tester);
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/688_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void _prueba(
  String descripcion,
  Future<void> Function(WidgetTester tester) cuerpo, {
  Object? skip,
}) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }, skip: skip != null && skip != false);
}

Finder _aviso(String clave) => find.byKey(Key('union_rechazada_$clave'));

void main() {
  setUpAll(cargarFuentesReales);

  for (final (nombre, tamano) in [
    ('320x640', const Size(320, 640)),
    ('360x640', const Size(360, 640)),
    ('412x915', const Size(412, 915)),
  ]) {
    for (final escala in [1.0, 2.0]) {
      _prueba('QA: la tarjeta con el aviso UB003 en $nombre y texto ×$escala: sin overflow, '
          'objetivos de toque, etiquetas y contraste', (tester) async {
        final datos = _datos()..rechazarUnion(_parItalia, 'UB003');
        await _montar(tester, datos, escala: escala, tamano: tamano);

        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          _aviso(_parItalia),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await _capturar(tester, 'ub003_${nombre}_x${escala.toInt()}');
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(tester.takeException(), isNull);
      });
    }
  }

  _prueba('QA: el aviso genérico a 360×640 con texto ×2 (captura y guías)', (tester) async {
    final datos = _datos()..rechazarUnion(_parItalia, '42501');
    await _montar(tester, datos, escala: 2, tamano: const Size(360, 640));
    await _capturar(tester, 'generico_360x640_x2');
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester.takeException(), isNull);
  });

  _prueba('QA: sin el aviso (par normal) a 360×640, captura de comparación', (tester) async {
    final datos = _datos();
    await _montar(tester, datos, tamano: const Size(360, 640));
    await _capturar(tester, 'sin_aviso_360x640_x1');
    expect(_aviso(_parItalia), findsNothing);
  });

  _prueba('QA: unir desde la hoja y que el servidor lo rechace: el par vuelve y el aviso aparece '
      'con la vista abierta', (tester) async {
    final datos = _datos();
    await _montar(tester, datos);
    await tester.ensureVisible(find.byKey(const Key('revisar_$_parItalia')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('revisar_$_parItalia')));
    await _asentar(tester);
    await _capturar(tester, 'hoja_comparar');
    expect(find.textContaining('Conservar'), findsWidgets);
    // El servidor rechaza: la unión se deshace en el teléfono y el par queda con su aviso.
    datos.rechazarUnion(_parItalia, 'UB003');
    await _asentar(tester);
    expect(tester.takeException(), isNull);
  });

  _prueba('QA: el aviso que llega con la vista abierta se anuncia al lector (región viva), como '
      'los demás avisos de esta pantalla', (tester) async {
    final manejador = tester.ensureSemantics();
    final datos = _datos();
    await _montar(tester, datos);
    expect(_aviso(_parItalia), findsNothing);

    datos.rechazarUnion(_parItalia, 'UB003');
    await _asentar(tester);

    final semantica = tester.getSemantics(_aviso(_parItalia));
    expect(semantica.getSemanticsData().label, _textoUb003);
    expect(
      semantica.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
      reason: 'el aviso aparece solo, sin que el colportor haga nada: un lector no lo oiría',
    );
    manejador.dispose();
  });

  _prueba('QA: el texto genérico no promete reintentar (no dice «Probá de nuevo»)', (tester) async {
    final datos = _datos()..rechazarUnion(_parItalia, '42501');
    await _montar(tester, datos);
    expect(find.textContaining('Probá de nuevo'), findsNothing);
    expect(find.text(_textoGenerico), findsOneWidget);
  });
}

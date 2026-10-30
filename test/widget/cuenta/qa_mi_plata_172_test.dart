// QA de «Mi plata» (vista 33C, HU-CTA-003, #172): lo que el test del implementador no recorre. Las
// cuatro guías de accesibilidad en cada estado (y con el texto al 200 %), el aviso de error que se
// anuncia, el cuerpo de la vista cuando el detalle cambia a mitad de camino, y las capturas de cada
// estado (a `.dart_tool/qa_capturas/`, gitignored: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/detalle_de_mi_plata.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/mi_plata_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/cuenta/presentation/widgets/piezas_mi_plata.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';

const _raiz = Key('qa_raiz_captura');

/// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true`.
const _sacarCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Carga las fuentes reales; sin ellas las capturas salen con cajas.
Future<void> _cargarFuentes() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
}

Future<void> _montar(
  WidgetTester tester,
  RepositorioDeDetalleControlable repo, {
  required CategoriaDeMiPlata abierta,
  required Size tamano,
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
    File('${dir.path}/172_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

final _conTodo = DetalleDeMiPlata(
  enManoCentavos: 50000,
  enMano: [
    MovimientoEnMano(cliente: 'Pedro Gómez', fecha: dia(20), centavos: 240000),
    MovimientoEnMano(cliente: 'Pedro Gómez', fecha: dia(21), centavos: -190000, esDevolucion: true),
  ],
  porCobrarCentavos: 970000,
  porCobrar: detalleDelCanvas.porCobrar,
  deboCentavos: 150000,
  deboAClientes: [SaldoDeCliente(cliente: 'Lucía Pérez', desde: dia(22), centavos: 150000)],
);

/// Cada estado de «Mi plata» con lo que hace falta para llegar a él.
final _estados = <String, (RepositorioDeDetalleControlable Function(), CategoriaDeMiPlata)>{
  '33C01_en_mano': (
    () => RepositorioDeDetalleControlable(inicial: detalleDelCanvas),
    CategoriaDeMiPlata.enMano,
  ),
  '33C02_por_cobrar': (
    () => RepositorioDeDetalleControlable(inicial: detalleDelCanvas),
    CategoriaDeMiPlata.porCobrar,
  ),
  '33C03_nada_en_mano': (
    () => RepositorioDeDetalleControlable(inicial: DetalleDeMiPlata.vacio),
    CategoriaDeMiPlata.enMano,
  ),
  'devolucion_y_debo_abierto': (
    () => RepositorioDeDetalleControlable(inicial: _conTodo),
    CategoriaDeMiPlata.deboAClientes,
  ),
  'error': (
    () => RepositorioDeDetalleControlable()..fallaAlSuscribir = true,
    CategoriaDeMiPlata.enMano,
  ),
  'cargando': (() => RepositorioDeDetalleControlable(), CategoriaDeMiPlata.enMano),
};

void main() {
  group('accesibilidad: las cuatro guías en cada estado', () {
    for (final tam in {'360x640': const Size(360, 640), '412x915': const Size(412, 915)}.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in _estados.entries) {
          testWidgets('${estado.key} a ${tam.key}, texto $escala', (tester) async {
            final handle = tester.ensureSemantics();
            final (repo, abierta) = estado.value;
            await _montar(tester, repo(), abierta: abierta, tamano: tam.value, escala: escala);

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
  });

  group('el aviso de error se anuncia y tiene salida', () {
    testWidgets('el error es una región viva con el texto, y «Reintentar» es un botón', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final repo = RepositorioDeDetalleControlable()..fallaAlSuscribir = true;
      await _montar(tester, repo, abierta: CategoriaDeMiPlata.enMano, tamano: const Size(360, 640));

      final aviso = tester.getSemantics(find.byKey(const Key('cuenta_error_texto')));
      expect(aviso, isSemantics(isLiveRegion: true));
      expect(aviso.label, contains('No pudimos calcular tu cuenta.'));
      expect(
        tester.getSemantics(find.byKey(const Key('cuenta_reintentar'))),
        isSemantics(isButton: true, label: 'Reintentar'),
      );
      handle.dispose();
    });

    testWidgets('con el error a la vista, el botón de volver sigue funcionando', (tester) async {
      final repo = RepositorioDeDetalleControlable()..fallaAlSuscribir = true;
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [detalleDeMiPlataRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: temaClaro(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => MiPlataPage.abrir(
                    context,
                    colportorId: 'col-1',
                    abierta: CategoriaDeMiPlata.enMano,
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuenta_reintentar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('mi_plata_volver')));
      await tester.pumpAndSettle();

      expect(find.byType(MiPlataPage), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
    });
  });

  group('el detalle cambia a mitad de camino', () {
    testWidgets('si la cifra pasa a cero con la categoría abierta, aparece el texto de vacío y no '
        'queda la lista vieja', (tester) async {
      final repo = RepositorioDeDetalleControlable(inicial: detalleDelCanvas);
      await _montar(tester, repo, abierta: CategoriaDeMiPlata.enMano, tamano: const Size(360, 640));
      expect(find.text('Pedro Gómez · 21/10'), findsOneWidget);

      repo.emitir(DetalleDeMiPlata.vacio);
      await tester.pumpAndSettle();

      expect(find.text('Pedro Gómez · 21/10'), findsNothing);
      expect(find.text('No tenés efectivo sin depositar.'), findsOneWidget);
    });

    testWidgets('si «Debo a clientes» estaba abierta y el compromiso se cumple, la pantalla no '
        'queda en blanco ni con un error', (tester) async {
      final repo = RepositorioDeDetalleControlable(inicial: _conTodo);
      await _montar(
        tester,
        repo,
        abierta: CategoriaDeMiPlata.deboAClientes,
        tamano: const Size(360, 640),
      );
      expect(find.text('Lucía Pérez · desde 22/10'), findsOneWidget);

      repo.emitir(detalleDelCanvas);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mi_plata_categoria_deboAClientes')), findsNothing);
      expect(find.byKey(const Key('mi_plata_categoria_enMano')), findsOneWidget);
      expect(find.byKey(const Key('mi_plata_categoria_porCobrar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('capturas de cada estado (a .dart_tool/qa_capturas/)', skip: !_sacarCapturas, () {
    setUpAll(_cargarFuentes);
    for (final tam in {'360x640': const Size(360, 640), '412x915': const Size(412, 915)}.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in _estados.entries) {
          testWidgets('${estado.key} ${tam.key} x$escala', (tester) async {
            final (repo, abierta) = estado.value;
            await _montar(tester, repo(), abierta: abierta, tamano: tam.value, escala: escala);
            await _capturar(tester, '${estado.key}_${tam.key}_x${escala.toInt()}');
          });
        }
      }
    }
  });
}

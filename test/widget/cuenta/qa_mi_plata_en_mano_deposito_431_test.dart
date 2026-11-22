// QA #431 r2: «En mano» con las filas de los depósitos que sacaron plata de la mano (decisión del
// 04/11): «Depósito · Casa editora · Banco · 12/10 — − $ 1.000» en rojo, entre los cobros. Las cuatro
// guías de accesibilidad, lo que lee el lector, el pliegue y el caso en que lo depositado supera lo
// cobrado (la cifra queda en $ 0). Capturas con `--dart-define=QA_CAPTURAS=true`.
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

const _raiz = Key('qa_raiz_captura_431b');
const _sacarCapturas = bool.fromEnvironment('QA_CAPTURAS');
const _tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

MovimientoEnMano _cobro(String cliente, int d, int pesos) =>
    MovimientoEnMano(cliente: cliente, fecha: dia(d), centavos: pesos * 100);

MovimientoEnMano _deposito(int pesos, int d, {bool validado = true}) => MovimientoEnMano(
  cliente: '',
  fecha: dia(d),
  centavos: -pesos * 100,
  deposito: depositoDe(pesos, d, validado: validado),
);

DetalleDeMiPlata _con(List<MovimientoEnMano> filas, int enManoPesos) => DetalleDeMiPlata(
  depositado: depositadoDelCanvas,
  enManoCentavos: enManoPesos * 100,
  enMano: filas,
  porCobrarCentavos: detalleDelCanvas.porCobrarCentavos,
  porCobrar: detalleDelCanvas.porCobrar,
);

/// 600 cobrados el 20, 1.200 el 21, un depósito por validar de 1.000 el 22 y uno validado de 500 el 23.
final _conDepositos = _con([
  _cobro('María Fernández', 20, 600),
  _cobro('Pedro Gómez', 21, 1200),
  _deposito(1000, 22, validado: false),
  _deposito(500, 23),
], 300);

/// Se depositó más de lo cobrado: la cifra no baja de cero.
final _depositoDeMas = _con([_cobro('María Fernández', 20, 600), _deposito(900, 22)], 0);

final _estados = {'con_depositos': _conDepositos, 'deposito_de_mas': _depositoDeMas};

Future<void> _montar(
  WidgetTester tester,
  DetalleDeMiPlata detalle, {
  required Size tamano,
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        detalleDeMiPlataRepositoryProvider.overrideWithValue(
          RepositorioDeDetalleControlable(inicial: detalle),
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: _raiz, child: child),
        ),
        home: const MiPlataPage(colportorId: 'col-1', abierta: CategoriaDeMiPlata.enMano),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _cargarFuentes() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await c.load();
  }
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/431b_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  group('«En mano» con depósitos', () {
    testWidgets(
      'cada depósito es una fila «Depósito · …» con el monto que baja, entre los cobros',
      (tester) async {
        await _montar(tester, _conDepositos, tamano: const Size(360, 900));

        expect(find.text(r'$ 300  ▴'), findsOneWidget);
        expect(find.text('Depósito · Casa editora · Banco · 22/10'), findsOneWidget);
        expect(find.text('Depósito · Casa editora · Banco · 23/10'), findsOneWidget);
        expect(find.text('− \$ 1.000'), findsOneWidget);
        expect(find.text('− \$ 500'), findsOneWidget);
        // En el orden de las fechas: los dos cobros primero, después los depósitos.
        final y = [
          for (final t in [
            'María Fernández · 20/10',
            'Pedro Gómez · 21/10',
            'Depósito · Casa editora · Banco · 22/10',
          ])
            tester.getTopLeft(find.text(t)).dy,
        ];
        expect(y, [...y]..sort());
      },
    );

    testWidgets('el lector lee la fila del depósito con el signo y no solo con el color', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, _conDepositos, tamano: const Size(360, 900));

      expect(
        find.bySemanticsLabel('Depósito · Casa editora · Banco · 22/10, − \$ 1.000'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('si lo depositado supera lo cobrado la cifra dice cero, no un negativo', (
      tester,
    ) async {
      await _montar(tester, _depositoDeMas, tamano: const Size(360, 900));

      expect(find.text(r'$ 0  ▴'), findsOneWidget);
      expect(find.textContaining('−  '), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final tam in _tamanos.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in _estados.entries) {
          testWidgets('guías de ${estado.key} a ${tam.key}, texto $escala', (tester) async {
            final handle = tester.ensureSemantics();
            await _montar(tester, estado.value, tamano: tam.value, escala: escala);

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

  group('capturas (a .dart_tool/qa_capturas/)', skip: !_sacarCapturas, () {
    setUpAll(_cargarFuentes);
    for (final tam in _tamanos.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in _estados.entries) {
          testWidgets('${estado.key} ${tam.key} x$escala', (tester) async {
            await _montar(tester, estado.value, tamano: tam.value, escala: escala);
            await _capturar(tester, '${estado.key}_${tam.key}_x$escala');
          });
        }
      }
    }
  });
}

// QA de «Entregado hoy» en el detalle de una cita de entrega y del acceso desde la pestaña Ventas
// (#435): sin overflow y con las guías de Flutter a 360×640 y 412×915, texto 1,0 y 2,0.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/detalle_agenda_arnes.dart';
import '../../helpers/entrega_diferida_ui_falsos.dart' show cumplidaCon;
import '../../helpers/entrega_falsos.dart';
import '../../helpers/qa_vista27_entrega_435_arnes.dart'
    show capturar435, cargarFuentes408, chico435, grande435, usarFuentesReales408;

const _tamanos = [chico435, grande435];
const _escalas = [1.0, 2.0];

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

DetalleDeAgenda _detalle() => DetalleDeAgenda(
  agenda: agendaDelDetalle(tipo: TipoAgenda.entrega, ventaId: 'v-1', entregaId: 'e-1'),
);

enum _Estado { programada, entregando, errorAlEntregar }

Future<EntornoDeEntrega> _montar(
  WidgetTester tester,
  _Estado estado,
  Size tamano,
  double escala,
) async {
  final e = EntornoDeEntrega();
  e.entregas.respuestaDeCumplir = cumplidaCon();
  switch (estado) {
    case _Estado.entregando:
      e.entregas.compuertaDeDiferida = Completer<void>();
    case _Estado.errorAlEntregar:
      e.entregas.fallasAlCumplir.add(const FailureEntregaNoGuardada());
    case _Estado.programada:
      break;
  }
  await montarDetalle(
    tester,
    detalle: _detalle(),
    conRegistrar: true,
    escala: escala,
    tamano: tamano,
    extra: e.overrides,
  );
  if (estado != _Estado.programada) {
    final boton = find.byKey(ClavesDetalleAgenda.entregadoHoy);
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await asentarDetalle(tester);
  }
  return e;
}

void main() {
  group('Detalle de la cita de entrega', () {
    for (final estado in _Estado.values) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          testWidgets(
            '${estado.name} · ${tamano.width.toInt()}×${tamano.height.toInt()} · ${escala}x',
            (tester) async {
              final handle = tester.ensureSemantics();
              final e = await _montar(tester, estado, tamano, escala);

              expect(tester.takeException(), isNull);
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              await expectLater(tester, meetsGuideline(textContrastGuideline));
              await capturar435(
                tester,
                'detalle_${estado.name}_${tamano.width.toInt()}x${tamano.height.toInt()}_'
                '${escala.toStringAsFixed(0)}x',
              );
              final c = e.entregas.compuertaDeDiferida;
              if (c != null && !c.isCompleted) c.complete();
              await asentarDetalle(tester);
              handle.dispose();
            },
          );
        }
      }
    }

    testWidgets('error al entregar: el botón sigue a mano y reintenta con una sola llamada', (
      tester,
    ) async {
      final e = await _montar(tester, _Estado.errorAlEntregar, chico435, 1);

      expect(find.textContaining('No pudimos guardar'), findsOneWidget);
      final boton = find.byKey(ClavesDetalleAgenda.entregadoHoy);
      expect(tester.widget<FilledButton>(boton).onPressed, isNotNull);
      await tester.tap(boton);
      await asentarDetalle(tester);

      expect(e.entregas.cumplidas, hasLength(2));
      expect(find.text('Entrega marcada.'), findsOneWidget);
    });
  });

  group('Con las fuentes reales: sin overflow y con captura', () {
    for (final estado in _Estado.values) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          testWidgets(
            '${estado.name} · ${tamano.width.toInt()}×${tamano.height.toInt()} · ${escala}x',
            (tester) async {
              usarFuentesReales408 = true;
              await cargarFuentes408(tester);
              final e = await _montar(tester, estado, tamano, escala);

              expect(tester.takeException(), isNull);
              await capturar435(
                tester,
                'detalleReal_${estado.name}_${tamano.width.toInt()}x${tamano.height.toInt()}_'
                '${escala.toStringAsFixed(0)}x',
              );
              final c = e.entregas.compuertaDeDiferida;
              if (c != null && !c.isCompleted) c.complete();
              await asentarDetalle(tester);
            },
          );
        }
      }
    }
  });

  group('Hallazgos (se corren con --dart-define=QA_HALLAZGOS=true)', () {
    // skip: QA #435 — con texto 2,0 el SnackBar del error de «Entregado hoy» tapa el botón con el que se
    // reintenta (360×640: aviso de 402 a 640 dp; 412×915: tapa la mitad del botón) y se va solo a los 4 s.
    for (final tamano in _tamanos) {
      testWidgets('el aviso de error de «Entregado hoy» no tapa el botón · ${tamano.width.toInt()}×'
          '${tamano.height.toInt()} · 2,0x', (tester) async {
        usarFuentesReales408 = true;
        await cargarFuentes408(tester);
        await _montar(tester, _Estado.errorAlEntregar, tamano, 2);

        final aviso = tester.getRect(find.byType(SnackBar));
        final boton = tester.getRect(find.byKey(ClavesDetalleAgenda.entregadoHoy));
        expect(aviso.overlaps(boton), isFalse, reason: 'aviso $aviso, botón $boton');
      }, skip: !_hallazgos);
    }
  });

  group('Pestaña Ventas · «Entregas pendientes»', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()} · ${escala}x', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          tester.view.physicalSize = tamano;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: temaClaro(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
                child: child!,
              ),
              home: Scaffold(
                body: PestanaProvisoria(
                  pestana: PestanaInicio.ventas,
                  alAbrirPrecios: () {},
                  alAbrirEntregas: () {},
                ),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.text('Entregas pendientes'), findsOneWidget);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await capturar435(
            tester,
            'pestana_ventas_${tamano.width.toInt()}x${tamano.height.toInt()}_'
            '${escala.toStringAsFixed(0)}x',
          );
          handle.dispose();
        });
      }
    }
  });
}

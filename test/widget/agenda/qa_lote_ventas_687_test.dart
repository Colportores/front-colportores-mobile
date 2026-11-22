// QA del lote de ventas (PR #687: #429, #435 vista 27C, #546, #466), el hilo de punta a punta con la
// app armada de verdad: casa → venta → entrega agendada → cobranza, y una entrevista con misionero
// sin venta, que no es una venta. Lo que ya prueba el implementador no se repite: acá, el recorrido
// entero, las guías de accesibilidad y la letra al 200 % del hilo, y las decisiones del 10/11.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/misionero_dejado.dart';
import 'package:colportores_mobile/features/agenda/domain/services/misioneros_para_dejar.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart'
    show ClavesAgendarVisita;
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/asi_quedo_la_venta_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/cuando_cobrar_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart' show diferidaPara;
import '../../helpers/entrega_falsos.dart';
import '../../helpers/qa_vista27_entrega_435_arnes.dart'
    show capturar435, cargarFuentes408, conCapturas408;
import '../../helpers/qa_vista39_venta_428_arnes.dart';
import '../../helpers/venta_ui_falsos.dart';

const _paginaOtroDia = Key('otro_dia_pagina');

final class _Misioneros implements MisionerosParaDejar {
  @override
  Future<List<MisioneroParaDejar>> leer() async => const [
    MisioneroParaDejar(productoId: 'p-camino', nombre: 'El camino a Cristo'),
  ];
}

/// Un repositorio que, al entregar ahora, deja una fila pendiente: la entrega parcial de 27B.
final class _EntregasQueDejanPendiente extends EntregasEnMemoria {
  @override
  Future<Either<Failure, EntregaRegistrada>> registrarEntrega(
    String ventaId,
    List<Entrega> filas, {
    DateTime? soloDesde,
  }) async {
    recibidas.add((ventaId: ventaId, filas: filas));
    return Right(
      EntregaRegistrada(
        entregas: [
          entregaDe('e-1', 'p-hijos', ventaId: ventaId),
          entregaDe('e-2', 'p-salud', ventaId: ventaId, pendiente: true),
        ],
      ),
    );
  }
}

void main() {
  late Arnes428 a;
  late EntornoDeEntrega entrega;

  setUp(() => a = Arnes428());

  /// Casa → «Sí, registrar la venta» → la venta armada → «Registrar» → 27A·14 «¿Y ahora?».
  Future<void> hastaYAhora(WidgetTester tester, {Size? tamano, double escala = 1}) async {
    entrega = EntornoDeEntrega();
    entrega.entregas.respuestaDeDiferir = diferidaPara(DateTime(2026, 10, 31, 16, 30));
    a.montaje.extra.addAll([
      ...entrega.overrides,
      cobrarDespuesDeLaVentaProvider.overrideWithValue((contexto) async => false),
    ]);
    await a.montar(tester, tamano: tamano ?? const Size(390, 844));
    await a.hastaLaVenta(tester);
    await a.armarLaVenta(tester);
    await tocar(tester, find.byKey(const Key('venta_cta')));
    await tester.pumpAndSettle();
    a.escala.value = escala;
    await tester.pumpAndSettle();
  }

  Future<void> elegirDiaYGuardar(WidgetTester tester) async {
    await tocar(tester, find.byKey(const Key('entrega_campo_fecha')));
    await tester.ensureVisible(find.byKey(ClavesAgendarVisita.dia(1)));
    await tester.tap(find.byKey(ClavesAgendarVisita.dia(1)));
    await tester.pump();
    await tester.ensureVisible(find.byKey(ClavesAgendarVisita.hojaListo));
    await tester.tap(find.byKey(ClavesAgendarVisita.hojaListo));
    await tester.pumpAndSettle();
    await tocar(tester, find.byKey(const Key('venta_cta')));
    await tester.pumpAndSettle();
  }

  group('de punta a punta: casa → venta → entrega agendada → cobranza', () {
    testWidgets(
      '«Entregar otro día» con día, «Otro día y hora» para cobrar: el cierre muestra las dos '
      'agendas y el mapa las nombra',
      (tester) async {
        await hastaYAhora(tester);
        await tocar(tester, find.text(TextosVenta.entregarOtroDia));
        await tocar(tester, find.text(TextosVenta.continuar));
        await tester.pumpAndSettle();
        expect(find.byKey(_paginaOtroDia), findsOneWidget);
        await elegirDiaYGuardar(tester);

        expect(entrega.entregas.diferidas, hasLength(1), reason: 'la entrega queda agendada');
        expect(find.byKey(ClavesCuandoCobrar.pagina), findsOneWidget);
        await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.otroDia)));
        await a.listoYGuardar(tester);

        expect(a.entorno.ventas.recibidas, hasLength(1), reason: 'una sola venta');
        expect(a.agendas.recibidas, hasLength(1), reason: 'una sola cobranza agendada');
        expect(entrega.entregas.diferidas, hasLength(1), reason: 'una sola entrega agendada');
        expect(a.devolvio, isTrue);
        expect(find.textContaining('Venta 0039 guardada. Entrega:'), findsOneWidget);
        expect(find.textContaining('Cobranza agendada'), findsOneWidget);
      },
    );

    testWidgets(
      'con la entrega agendada y «Sin fecha» la cobranza no se agenda, y el mapa lo dice',
      (tester) async {
        await hastaYAhora(tester);
        await tocar(tester, find.text(TextosVenta.entregarOtroDia));
        await tocar(tester, find.text(TextosVenta.continuar));
        await tester.pumpAndSettle();
        await elegirDiaYGuardar(tester);
        await a.sinFecha(tester);

        expect(a.agendas.recibidas, isEmpty);
        expect(entrega.entregas.diferidas, hasLength(1));
        expect(find.textContaining('Cobranza sin fecha'), findsOneWidget);
      },
    );

    testWidgets('cerrar el cierre con atrás no duplica la venta ni la entrega', (tester) async {
      await hastaYAhora(tester);
      await tocar(tester, find.byKey(const Key('venta_terminar')));
      await tester.pumpAndSettle();
      await elegirDiaYGuardar(tester);
      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
      await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(a.entorno.ventas.recibidas, hasLength(1));
      expect(entrega.entregas.diferidas, hasLength(1));
    });
  });

  group('una entrevista con misionero y sin venta no es una venta', () {
    testWidgets('«Lo que dejaste» guarda la visita y no crea venta, entrega ni cobranza', (
      tester,
    ) async {
      entrega = EntornoDeEntrega();
      a.montaje.extra
        ..addAll(entrega.overrides)
        ..add(misionerosParaDejarProvider.overrideWithValue(_Misioneros()));
      await a.montar(tester);
      await a.tocarKey(tester, const Key('abrir'));
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);
      await tester.ensureVisible(find.byTooltip('Uno más de El camino a Cristo'));
      await tester.tap(find.byTooltip('Uno más de El camino a Cristo'));
      await tester.pump();
      await a.tocarKey(tester, ClavesEntrevista.guardarLoQueDejaste);

      expect(a.montaje.agenda.recibidas, hasLength(1), reason: 'la visita sí se guarda');
      expect(a.entorno.ventas.recibidas, isEmpty, reason: 'un misionero no es una venta');
      expect(entrega.entregas.diferidas, isEmpty);
      expect(entrega.entregas.recibidas, isEmpty);
      expect(a.agendas.recibidas, isEmpty);
      expect(find.byKey(ClavesCierreDeVenta.pagina), findsNothing);
      expect(find.byKey(_paginaOtroDia), findsNothing);
    });
  });

  group('accesibilidad del hilo con la entrega', () {
    testWidgets('42B·01G a 360×640 con letra al 200 %: las dos tarjetas se alcanzan y no quedan '
        'bajo «Volver al mapa»', (tester) async {
      await hastaYAhora(tester, tamano: const Size(360, 640), escala: 2);
      await tocar(tester, find.byKey(const Key('venta_terminar')));
      await tester.pumpAndSettle();
      await elegirDiaYGuardar(tester);
      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
      await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));

      for (final tarjeta in [
        ClavesCierreDeVenta.tarjetaEntrega,
        ClavesCierreDeVenta.tarjetaCobranza,
      ]) {
        await tester.scrollUntilVisible(find.byKey(tarjeta), 80);
        await tester.pumpAndSettle();
        final alto = tester.getRect(find.byKey(tarjeta)).bottom;
        final cta = tester.getRect(find.byKey(ClavesCierreDeVenta.volver)).top;
        expect(alto, lessThanOrEqualTo(cta + 0.5), reason: 'la tarjeta queda bajo el botón fijo');
      }
    });

    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final letra in const [1.0, 2.0]) {
        final rotulo = '${tamano.width.toInt()}×${tamano.height.toInt()} · ${letra}x';

        testWidgets('27A·14 con «Entregar otro día» · $rotulo', (tester) async {
          final handle = tester.ensureSemantics();
          await hastaYAhora(tester, tamano: tamano, escala: letra);
          await tester.scrollUntilVisible(find.text(TextosVenta.entregarOtroDia), 100);
          expect(find.text(TextosVenta.entregarOtroDia), findsOneWidget);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          expect(tester.takeException(), isNull);
          handle.dispose();
        });

        testWidgets('42B·01G el cierre con «Entrega agendada» · $rotulo', (tester) async {
          final handle = tester.ensureSemantics();
          await hastaYAhora(tester, tamano: tamano, escala: letra);
          await tocar(tester, find.byKey(const Key('venta_terminar')));
          await tester.pumpAndSettle();
          await elegirDiaYGuardar(tester);
          await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
          await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));

          expect(find.byKey(ClavesCierreDeVenta.tarjetaEntrega), findsOneWidget);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          expect(tester.takeException(), isNull);
          handle.dispose();
        });
      }
    }
  });

  // Capturas para mirar (solo con `--dart-define=QA_CAPTURAS=true`, a `.dart_tool/qa_capturas/`).
  group('capturas', () {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final letra in const [1.0, 2.0]) {
        final rotulo = '${tamano.width.toInt()}_${letra.toInt()}x';

        testWidgets('27A·14 y 42B·01G · $rotulo', (tester) async {
          if (!conCapturas408) return;
          await cargarFuentes408(tester);
          await hastaYAhora(tester, tamano: tamano, escala: letra);
          await capturar435(tester, '687_27A14_$rotulo');
          await tocar(tester, find.byKey(const Key('venta_terminar')));
          await tester.pumpAndSettle();
          await capturar435(tester, '687_27C01_desde_01G_$rotulo');
          await elegirDiaYGuardar(tester);
          await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
          await capturar435(tester, '687_42B01B_$rotulo');
          await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
          await capturar435(tester, '687_42B01G_$rotulo');
        });
      }
    }
  });

  group('decisiones del 10/11 de #435 y revisión del PR', () {
    // P2: tras una entrega parcial se abre 27C·01 para lo que quedó; atrás = sin fecha.
    testWidgets(
      'P2: una entrega parcial en «Entregar ahora» abre 27C·01 para lo que quedó; atrás es sin fecha',
      (tester) async {
        entrega = EntornoDeEntrega(entregas: _EntregasQueDejanPendiente());
        a.montaje.extra.addAll([
          ...entrega.overrides,
          cobrarDespuesDeLaVentaProvider.overrideWithValue((contexto) async => false),
        ]);
        await a.montar(tester);
        await a.hastaLaVenta(tester);
        await a.armarLaVenta(tester);
        await tocar(tester, find.byKey(const Key('venta_cta')));
        await tester.pumpAndSettle();
        await tocar(tester, find.text(TextosVenta.entregarAhora));
        await tocar(tester, find.text(TextosVenta.continuar));
        await tocar(tester, find.byKey(const Key('venta_cta')));
        await tester.pumpAndSettle();

        expect(find.byKey(_paginaOtroDia), findsOneWidget);
        await tocar(tester, find.byKey(const Key('venta_atras')));
        await tester.pumpAndSettle();
        expect(find.byKey(ClavesCuandoCobrar.pagina), findsOneWidget, reason: 'atrás = sin fecha');
      },
    );

    testWidgets(
      'con la entrega ya agendada, si el cobro se cancela «¿Y ahora?» no vuelve a ofrecer entregar',
      (tester) async {
        await hastaYAhora(tester);
        await tocar(tester, find.text(TextosVenta.entregarOtroDia));
        await tocar(tester, find.text(TextosVenta.cobrarAhora));
        await tocar(tester, find.text(TextosVenta.continuar));
        await tester.pumpAndSettle();
        await elegirDiaYGuardar(tester);

        expect(find.byKey(const Key('venta_registrada_pagina')), findsOneWidget);
        expect(find.text(TextosVenta.entregarAhora), findsNothing);
        expect(find.text(TextosVenta.entregarOtroDia), findsNothing);
        expect(find.text(TextosVenta.cobrarAhora), findsOneWidget, reason: 'el cobro sigue a mano');
        expect(
          entrega.entregas.diferidas,
          hasLength(1),
          reason: 'la entrega quedó agendada una vez',
        );
      },
    );
  });
}

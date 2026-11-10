// QA de #432: el hilo entero con la app armada de verdad (aviso fijo → R·05 → R·06 → «Lo que dejaste»
// o venta → «¿Y ahora?» → «Entregar ahora» → cobro → «¿Cuándo volvés a cobrar?»). Lo que ya prueba el
// implementador no se repite: acá, lo que guarda la visita, el cobro que se cancela en 27B·04 y los
// artboards de la vista 42 (42B·01B a 01G, 42B·08) que el PR todavía no dibuja (hallazgos con `skip`;
// `--dart-define=QA_HALLAZGOS=true` los corre).
import 'package:colportores_mobile/features/agenda/domain/entities/misionero_dejado.dart';
import 'package:colportores_mobile/features/agenda/domain/services/misioneros_para_dejar.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_cuando_cobrar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_falsos.dart' show EntornoDeEntrega;
import '../../helpers/entrevista_falsos.dart';
import '../../helpers/qa_venta_432_arnes.dart';
import '../../helpers/qa_vista39_venta_428_arnes.dart';
import '../../helpers/venta_ui_falsos.dart';

final class _Misioneros implements MisionerosParaDejar {
  @override
  Future<List<MisioneroParaDejar>> leer() async => const [
    MisioneroParaDejar(productoId: 'p-camino', nombre: 'El camino a Cristo'),
    MisioneroParaDejar(productoId: 'p-esperanza', nombre: 'La gran esperanza'),
  ];
}

void main() {
  late Arnes428 a;

  setUp(() => a = Arnes428());

  Future<void> hastaLoQueDejaste(WidgetTester tester) async {
    await a.tocarKey(tester, const Key('abrir'));
    await a.tocarKey(tester, ClavesEntrevista.finalizar);
    await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);
  }

  Future<void> unoMas(WidgetTester tester, String nombre, {int veces = 1}) async {
    for (var i = 0; i < veces; i++) {
      await tester.ensureVisible(find.byTooltip('Uno más de $nombre'));
      await tester.tap(find.byTooltip('Uno más de $nombre'));
      await tester.pump();
    }
  }

  group('entrevista sin venta con «Lo que dejaste»', () {
    testWidgets('la visita guarda las horas de R·06 y los misioneros, atados a ella', (
      tester,
    ) async {
      a.montaje.extra.add(misionerosParaDejarProvider.overrideWithValue(_Misioneros()));
      await a.montar(tester);
      await hastaLoQueDejaste(tester);
      await unoMas(tester, 'El camino a Cristo', veces: 2);
      await unoMas(tester, 'La gran esperanza');
      await a.tocarKey(tester, ClavesEntrevista.guardarLoQueDejaste);

      final guardada = a.montaje.agenda.recibidas.single.visita;
      expect(guardada.entrevistaEntrada, inicioEntrevista.toUtc());
      expect(guardada.entrevistaSalida, ahoraEntrevista.toUtc());
      final dejados = a.montaje.agenda.misionerosPorVisita[guardada.id]!;
      expect(
        {for (final m in dejados) m.productoId: m.cantidad},
        {'p-camino': 2, 'p-esperanza': 1},
      );
      expect(dejados.every((m) => m.visitaId == guardada.id), isTrue);
      expect({for (final m in dejados) m.id}, hasLength(2), reason: 'un id por renglón');
      expect(find.byKey(ClavesEntrevista.loQueDejaste), findsNothing);
    });

    testWidgets('«No, guardar y volver al mapa» con el catálogo ilegible guarda sin el paso', (
      tester,
    ) async {
      // Sin override, `misionerosParaDejarProvider` lanza (base cerrada): el paso se salta.
      await a.montar(tester);
      await a.tocarKey(tester, const Key('abrir'));
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

      expect(find.byKey(ClavesEntrevista.loQueDejaste), findsNothing);
      expect(a.montaje.agenda.recibidas, hasLength(1));
      expect(a.montaje.agenda.misionerosPorVisita.values.single, isEmpty);
    });

    testWidgets('el aviso de guardado dice lo mismo que sin misioneros (diseño provisorio)', (
      tester,
    ) async {
      a.montaje.extra.add(misionerosParaDejarProvider.overrideWithValue(_Misioneros()));
      await a.montar(tester);
      await hastaLoQueDejaste(tester);
      await unoMas(tester, 'El camino a Cristo', veces: 3);
      await a.tocarKey(tester, ClavesEntrevista.guardarLoQueDejaste);

      expect(find.textContaining('Entrevista dada'), findsOneWidget);
    });

    // skip: QA #432 — 42B·08E: el toast de guardado dice «Entrevista guardada. Dejaste 3 misioneros.»
    // con «Deshacer»; la app dice «Guardado. <lugar> quedó como «Entrevista dada».» sin los misioneros.
    testWidgets('42B·08E: «Entrevista guardada. Dejaste 3 misioneros.» con «Deshacer»', (
      tester,
    ) async {
      a.montaje.extra.add(misionerosParaDejarProvider.overrideWithValue(_Misioneros()));
      await a.montar(tester);
      await hastaLoQueDejaste(tester);
      await unoMas(tester, 'El camino a Cristo', veces: 3);
      await a.tocarKey(tester, ClavesEntrevista.guardarLoQueDejaste);

      expect(find.text('Entrevista guardada. Dejaste 3 misioneros.'), findsOneWidget);
      expect(find.text('Deshacer'), findsOneWidget);
    }, skip: !verHallazgos);
  });

  group('venta → «Entregar ahora» → cobro', () {
    late EntornoDeEntrega entrega;

    Future<void> hastaLaEntregaConSaldo(WidgetTester tester) async {
      entrega = EntornoDeEntrega();
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
    }

    // skip: QA #432 — «Cobrar ahora» de 27B·04 abre el cobro y «vuelve a mostrar la venta con lo que
    // quedó» (cuerpo del PR). Si la colportora se arrepiente y sale del cobro sin cobrar nada, la app
    // la lleva a «¿Cuándo volvés a cobrar?» en vez de dejarla en 27B·04.
    testWidgets('salir del cobro sin cobrar deja a la colportora en 27B·04', (tester) async {
      await hastaLaEntregaConSaldo(tester);
      expect(find.text('Entrega registrada'), findsOneWidget);

      await tocar(tester, find.text('Cobrar ahora'));

      expect(find.byKey(const Key('entrega_pagina')), findsOneWidget);
      expect(find.byKey(ClavesCuandoCobrar.hoja), findsNothing);
    }, skip: !verHallazgos);

    // skip: QA #432 — 42B·01B: «¿Cuándo volvés a cobrar?» es una pantalla («VENTA 0039», «Pedro Gómez ·
    // saldo $ 3.000») con las ayudas «Más tarde, en esta misma salida», «Elegís el día y la hora»,
    // «Queda en tus cobranzas, sin día ni aviso» y el botón «Guardar» que se prende al elegir; la app
    // tiene una hoja con otras ayudas y sin «Guardar» (elegir cierra).
    testWidgets('42B·01B: la pregunta con las ayudas y el «Guardar» del diseño', (tester) async {
      await hastaLaEntregaConSaldo(tester);
      await tocar(tester, find.text('Volver al mapa'));

      expect(find.text('Más tarde, en esta misma salida'), findsOneWidget);
      expect(find.text('Queda en tus cobranzas, sin día ni aviso'), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
    }, skip: !verHallazgos);

    // skip: QA #432 — 42B·01D a 01G: el cierre único «Así quedó la venta» (Entrega, Cobro, Saldo, la
    // cobranza agendada o la entrega agendada y «Volver al mapa»); la app termina con un SnackBar.
    testWidgets('42B·01E: el cierre «Así quedó la venta» con Entrega, Cobro y Saldo', (
      tester,
    ) async {
      await hastaLaEntregaConSaldo(tester);
      await tocar(tester, find.text('Volver al mapa'));
      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));

      expect(find.text('Así quedó la venta'), findsOneWidget);
      expect(find.text('✓ Entregada hoy'), findsOneWidget);
      expect(find.text('Sin cobrar'), findsOneWidget);
    }, skip: !verHallazgos);

    testWidgets('«Sin fecha» termina el hilo sin agendar nada ni dejar la entrega a medias', (
      tester,
    ) async {
      await hastaLaEntregaConSaldo(tester);
      await tocar(tester, find.text('Volver al mapa'));
      await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));

      expect(a.agendas.recibidas, isEmpty);
      expect(entrega.entregas.recibidas, isNotEmpty);
      expect(a.devolvio, isTrue);
      expect(find.byKey(ClavesCuandoCobrar.hoja), findsNothing);
    });
  });
}

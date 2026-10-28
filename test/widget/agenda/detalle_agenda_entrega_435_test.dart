// HU-VEN-003 (#435) — el detalle de una cita de ENTREGA (vista 23, 23C·01): «Registrar resultado» no
// va (abriría una visita, no una entrega) y en su lugar está «Entregado hoy», que marca como entregado
// todo lo pendiente de la venta con una sola llamada aunque se toque dos veces; más sus casos límite.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_diferida.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/detalle_agenda_arnes.dart';
import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';

Finder get _entregadoHoy => find.byKey(ClavesDetalleAgenda.entregadoHoy);

DetalleDeAgenda _detalleDeEntrega({String? ventaId = 'v-1'}) => DetalleDeAgenda(
  agenda: agendaDelDetalle(
    tipo: TipoAgenda.entrega,
    ventaId: ventaId,
    entregaId: ventaId == null ? null : 'e-1',
  ),
);

/// El repositorio que explota en vez de contestar (un error que ningún `Either` previó).
class _RepoQueExplota extends EntregasEnMemoria {
  @override
  Future<Either<Failure, EntregaCumplida>> cumplir(
    String ventaId, {
    required DateTime ahora,
    required String idDeLaCita,
    Set<String>? entregaIds,
    DateTime? nuevaFecha,
  }) => throw StateError('sin base abierta');
}

Future<EntornoDeEntrega> _montar(
  WidgetTester tester, {
  DetalleDeAgenda? detalle,
  EntornoDeEntrega? entorno,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool conRegistrar = true,
}) async {
  final e = entorno ?? EntornoDeEntrega();
  if (entorno == null) e.entregas.respuestaDeCumplir = cumplidaCon();
  await montarDetalle(
    tester,
    detalle: detalle ?? _detalleDeEntrega(),
    conRegistrar: conRegistrar,
    escala: escala,
    tamano: tamano,
    extra: e.overrides,
  );
  return e;
}

Future<void> _tocarEntregadoHoy(WidgetTester tester) async {
  await tester.ensureVisible(_entregadoHoy);
  await tester.tap(_entregadoHoy);
  await asentarDetalle(tester);
}

void main() {
  group('la cita de entrega', () {
    testWidgets('no ofrece «Registrar resultado» y sí «Entregado hoy»', (tester) async {
      await _montar(tester);

      expect(find.byKey(ClavesDetalleAgenda.registrar), findsNothing);
      expect(find.text('Registrar resultado'), findsNothing);
      expect(_entregadoHoy, findsOneWidget);
      expect(find.text('Entregado hoy'), findsOneWidget);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
      expect(find.text('Cancelar agenda'), findsOneWidget);
    });

    testWidgets('una entrevista sigue con «Registrar resultado» y sin «Entregado hoy»', (
      tester,
    ) async {
      await _montar(tester, detalle: DetalleDeAgenda(agenda: agendaDelDetalle()));

      expect(find.byKey(ClavesDetalleAgenda.registrar), findsOneWidget);
      expect(_entregadoHoy, findsNothing);
    });

    testWidgets('una cita de entrega sin venta no puede marcar nada: no ofrece el botón', (
      tester,
    ) async {
      await _montar(tester, detalle: _detalleDeEntrega(ventaId: null));

      expect(_entregadoHoy, findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.registrar), findsNothing);
    });

    testWidgets('«Entregado hoy» marca todo lo pendiente de la venta y lo avisa', (tester) async {
      final e = await _montar(tester);

      await _tocarEntregadoHoy(tester);

      final llamada = e.entregas.cumplidas.single;
      expect(llamada.ventaId, 'v-1');
      expect(llamada.entregaIds, isNull, reason: 'sin ids: todo lo que siga pendiente');
      expect(llamada.nuevaFecha, isNull);
      expect(find.text('Entrega marcada.'), findsOneWidget);
      expect(_entregadoHoy, findsOneWidget);
    });

    testWidgets('sin conexión funciona igual y no menciona la señal', (tester) async {
      final e = await _montar(tester);

      await _tocarEntregadoHoy(tester);

      expect(e.entregas.cumplidas, hasLength(1));
      expect(find.textContaining('conexión'), findsNothing);
    });

    testWidgets('si ya estaba entregada (segundo «Entregado hoy»), lo dice sin alarmar', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.entregas.respuestaDeCumplir = cumplidaCon(yaEstaba: true);
      await _montar(tester, entorno: e);

      await _tocarEntregadoHoy(tester);

      expect(find.text('Esa entrega ya estaba marcada como entregada.'), findsOneWidget);
    });
  });

  group('casos límite', () {
    testWidgets('doble toque: una sola llamada y el botón queda ocupado hasta que termine', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.entregas.respuestaDeCumplir = cumplidaCon();
      e.entregas.compuertaDeDiferida = Completer<void>();
      await _montar(tester, entorno: e);

      await tester.ensureVisible(_entregadoHoy);
      await tester.tap(_entregadoHoy);
      await tester.pump();
      await tester.tap(_entregadoHoy, warnIfMissed: false);
      await tester.pump();

      expect(e.entregas.cumplidas, hasLength(1));
      expect(tester.widget<FilledButton>(_entregadoHoy).onPressed, isNull);
      expect(
        find.descendant(of: _entregadoHoy, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );

      e.entregas.compuertaDeDiferida!.complete();
      await asentarDetalle(tester);

      expect(e.entregas.cumplidas, hasLength(1));
      expect(tester.widget<FilledButton>(_entregadoHoy).onPressed, isNotNull);
      expect(find.text('Entrega marcada.'), findsOneWidget);
    });

    testWidgets('falla a mitad: avisa qué pasó, el botón vuelve y el reintento marca', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.entregas.respuestaDeCumplir = cumplidaCon();
      e.entregas.fallasAlCumplir.add(const FailureEntregaNoGuardada());
      await _montar(tester, entorno: e);

      await _tocarEntregadoHoy(tester);

      expect(find.textContaining('No pudimos guardar la entrega en tu teléfono'), findsOneWidget);
      expect(tester.widget<FilledButton>(_entregadoHoy).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _tocarEntregadoHoy(tester);

      expect(e.entregas.cumplidas, hasLength(2));
      expect(find.text('Entrega marcada.'), findsOneWidget);
    });

    testWidgets('una excepción que nadie previó tampoco deja el botón trabado', (tester) async {
      final e = EntornoDeEntrega(entregas: _RepoQueExplota());
      await _montar(tester, entorno: e);

      await _tocarEntregadoHoy(tester);

      expect(find.textContaining('No pudimos guardar la entrega'), findsOneWidget);
      expect(tester.widget<FilledButton>(_entregadoHoy).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('volver y reentrar: el botón está disponible y no quedó nada ocupado', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _tocarEntregadoHoy(tester);

      await tester.tap(find.byKey(ClavesDetalleAgenda.volver));
      await asentarDetalle(tester);
      await abrirDetalle(tester);

      expect(tester.widget<FilledButton>(_entregadoHoy).onPressed, isNotNull);
      expect(e.entregas.cumplidas, hasLength(1));
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'texto al ${(escala * 100).round()} % a 320 × 568: nada desborda y el botón se alcanza',
        (tester) async {
          final e = await _montar(tester, escala: escala, tamano: const Size(320, 568));

          expect(tester.takeException(), isNull);
          await tester.ensureVisible(_entregadoHoy);
          expect(tester.getSize(_entregadoHoy).height, greaterThanOrEqualTo(48));
          await _tocarEntregadoHoy(tester);
          expect(tester.takeException(), isNull);
          expect(e.entregas.cumplidas, hasLength(1));
        },
      );
    }
  });
}

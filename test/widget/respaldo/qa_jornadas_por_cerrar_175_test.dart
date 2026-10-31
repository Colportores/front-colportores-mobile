// QA de la pantalla «¿A qué hora terminaste?» que sigue a la recuperación (HU-JOR-002, #175): el texto,
// volver atrás desde la hora sin cerrar, los dos números de jornadas y las guías de accesibilidad en
// 360x640 y 412x915 con texto 1,0 y 2,0.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/usecases/jornadas_por_cerrar_use_case.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/jornadas_por_cerrar_page.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_recuperacion_175_arnes.dart';

DateTime _hoy(int h, [int m = 0]) => DateTime(2026, 10, 22, h, m);

JornadaPorCerrar _por(String id, DateTime inicio, DateTime siguiente) => JornadaPorCerrar(
  jornada: Jornada(
    id: id,
    colportorId: usuarioDePrueba,
    inicio: inicio,
    auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: usuarioDePrueba),
  ),
  inicioSiguiente: siguiente,
);

final _pagina = find.byKey(const Key('jornadas_por_cerrar_pagina'));
final _elegir = find.byKey(const Key('jornadas_por_cerrar_elegir'));
final _cerrar = find.byKey(const Key('corregir_jornada_cerrar'));

/// Monta la pantalla con [cuantas] jornadas por cerrar y vuelve atrás de la hora que abre sola.
Future<void> _montar(
  WidgetTester tester, {
  int cuantas = 2,
  Size tamano = chico175,
  double escala = 1,
  bool volver = true,
}) async {
  fijarTelefono(tester, tamano: tamano, escala: escala);
  final pendientes = [for (var i = 0; i < cuantas; i++) _por('j$i', _hoy(8 + i), _hoy(9 + i))];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [relojJornadaProvider.overrideWithValue(() => _hoy(18))],
      child: MaterialApp(
        theme: temaClaro().copyWith(splashFactory: NoSplash.splashFactory),
        home: JornadasPorCerrarPage(sesion: sesionDePrueba(), pendientes: pendientes),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (volver) {
    expect(_cerrar, findsOneWidget, reason: 'la hora se abre sola');
    await _salir(tester);
  }
}

/// Saca la pantalla de la hora a la fuerza (el «atrás» del sistema está bloqueado mientras haya una
/// hora válida): simula el caso en que el reloj no deja ninguna.
Future<void> _salir(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pumpAndSettle();
}

void main() {
  group('HU-JOR-002 tras recuperar: pantalla «¿A qué hora terminaste?»', () {
    testWidgets('con una más vieja: el texto en plural y la jornada con su día y hora', (
      tester,
    ) async {
      await _montar(tester, cuantas: 2);
      expect(
        find.text(
          'Quedaron abiertas 2 jornadas de antes. Indicá a qué hora terminó cada una; no las '
          'cerramos con la hora de ahora porque las horas se contarían dos veces.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('a las 08:00'), findsOneWidget);
      expect(find.textContaining('Empezó el '), findsOneWidget);
    });

    testWidgets('con una sola: el texto en singular', (tester) async {
      await _montar(tester, cuantas: 1);
      expect(find.textContaining('Quedó abierta una jornada de antes'), findsOneWidget);
    });

    testWidgets('el «atrás» del sistema no deja salir de la hora sin cerrar la jornada', (
      tester,
    ) async {
      await _montar(tester, volver: false);
      expect(_cerrar, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_cerrar, findsOneWidget, reason: 'sigue en «¿A qué hora terminaste?»');
    });

    testWidgets('volver atrás de la hora no cierra nada y «Elegir la hora de fin» la reabre una '
        'sola vez', (tester) async {
      await _montar(tester);
      expect(_pagina, findsOneWidget);
      expect(_cerrar, findsNothing);
      await tester.tap(_elegir);
      await tester.tap(_elegir, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_cerrar, findsOneWidget);
      await _salir(tester);
      expect(_cerrar, findsNothing, reason: 'una sola pantalla de hora abierta, no dos');
      expect(_pagina, findsOneWidget);
    });

    for (final tamano in [chico175, grande175]) {
      for (final escala in [1.0, 2.0]) {
        group(sufijo175(tamano, escala), () {
          testWidgets('sin overflow y el botón se alcanza', (tester) async {
            await _montar(tester, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(_elegir);
            await tester.pump();
            final r = tester.getRect(_elegir);
            final v = tester.view.physicalSize / tester.view.devicePixelRatio;
            expect(
              r.left >= 0 && r.right <= v.width && r.bottom <= v.height,
              isTrue,
              reason: '$r en $v',
            );
          });

          for (final (nombre, guia) in [
            ('toque Android', androidTapTargetGuideline),
            ('toque iOS', iOSTapTargetGuideline),
            ('nombre en lo tocable', labeledTapTargetGuideline),
            ('contraste', textContrastGuideline),
          ]) {
            testWidgets('guía de $nombre', (tester) async {
              final h = tester.ensureSemantics();
              await _montar(tester, tamano: tamano, escala: escala);
              await expectLater(tester, meetsGuideline(guia));
              h.dispose();
            });
          }
        });
      }
    }
  });
}

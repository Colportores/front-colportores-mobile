// QA #429 (HU-VEN-005, vista 32B·01): «Entregar» en la tarjeta de la entrega pendiente.
// Matriz de estados × 360×640 / 412×915 × letra 1,0 / 2,0 con las guías de accesibilidad, sin
// desborde, el nodo de semántica y casos límite que el implementador no cubrió.
import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

void main() {
  final prevista = DateTime(2026, 10, 24, 12);

  EntregaEnFicha pendiente(
    String id, {
    String? ventaId = 'ven-1',
    String producto = 'Nuestros Hijos',
    int cantidad = 1,
  }) => EntregaEnFicha(
    id: id,
    fecha: prevista,
    pendiente: true,
    ventaId: ventaId,
    lineas: [LineaDeFicha(nombre: producto, cantidad: cantidad)],
  );

  List<MovimientoDeFicha> historial(List<MovimientoDeFicha> extra) => [
    ...extra,
    CobroEnFicha(
      id: 'cob-1',
      fecha: DateTime(2026, 10, 20, 12),
      montoCentavos: 60000,
      efectivo: true,
      ventaId: 'ven-1',
      numeroTalonario: '0042',
    ),
    ...historialDelCanvas(),
  ];

  MundoFicha mundo(List<MovimientoDeFicha> extra, {bool conDestino = true, MundoFicha? base}) {
    final m = base ?? MundoFicha(historial: historial(extra));
    m
      ..conRegistrarEntrega = conDestino
      ..cuentas.cuenta = cuentaConSaldo;
    return m;
  }

  Finder entregar(String id) => find.byKey(ClavesFicha.entregar(id));
  Finder fila(String id) => find.byKey(ClavesFicha.fila(id));

  /// La lista es perezosa: baja hasta que la tarjeta exista y la deja a la vista.
  Future<void> aVista(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 100));
  }

  void sinExcepcion(WidgetTester tester, String donde) {
    final e = tester.takeException();
    expect(e, isNull, reason: 'desborde o error en $donde: $e');
  }

  const tamanos = <(String, Size)>[('360×640', Size(360, 640)), ('412×915', Size(412, 915))];
  const escalas = <double>[1, 2];

  // (nombre, mundo, id de la tarjeta a mirar, ¿ofrece «Entregar»?)
  final estados = <(String, MundoFicha Function(), String, bool)>[
    ('una pendiente', () => mundo([pendiente('p1')]), 'p1', true),
    (
      'dos pendientes de ventas distintas',
      () => mundo([pendiente('p1'), pendiente('p2', ventaId: 'ven-2', producto: 'Salud y Hogar')]),
      'p2',
      true,
    ),
    (
      'producto de nombre muy largo',
      () => mundo([
        pendiente(
          'p1',
          producto: 'El conflicto de los siglos, edición ilustrada para toda la familia',
          cantidad: 12,
        ),
      ]),
      'p1',
      true,
    ),
    ('sin destino', () => mundo([pendiente('p1')], conDestino: false), 'p1', false),
    (
      'persona de baja (32B·04)',
      () => mundo(
        const [],
        base: MundoFicha(
          persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
          historial: historial([pendiente('p1')]),
          notasIniciales: notasDeLaFicha(),
          contexto: contextoBajaDesde22(),
        ),
      ),
      'p1',
      false,
    ),
    (
      'depto de baja (32B·08)',
      () => mundo(
        const [],
        base: MundoFicha(
          historial: historial([pendiente('p1')]),
          notasIniciales: notasDeLaFicha(),
          contexto: contextoDeptoDeBaja,
        ),
      ),
      'p1',
      false,
    ),
  ];

  group('guías de accesibilidad y desborde por estado y tamaño', () {
    for (final (tn, tam) in tamanos) {
      for (final esc in escalas) {
        for (final (nombre, crear, id, ofrece) in estados) {
          testWidgets('$nombre · $tn · letra $esc×', (tester) async {
            final semantica = tester.ensureSemantics();
            await montarFicha(tester, crear(), tamano: tam, escala: esc);
            sinExcepcion(tester, 'montar $nombre $tn $esc');
            await aVista(tester, fila(id));
            sinExcepcion(tester, 'scroll $nombre $tn $esc');

            expect(tester.getSize(fila(id)).height, greaterThanOrEqualTo(48));
            if (ofrece) {
              final caja = tester.getRect(fila(id));
              final boton = tester.getRect(entregar(id));
              expect(
                caja.contains(boton.topLeft) && caja.contains(boton.bottomRight),
                isTrue,
                reason: '«Entregar» queda dentro de su tarjeta',
              );
            } else {
              expect(find.text('Entregar'), findsNothing);
            }

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });

  group('semántica', () {
    testWidgets('la tarjeta con «Entregar» es un botón habilitado con acción de tocar', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, mundo([pendiente('p1')]), tamano: const Size(360, 640));
      await aVista(tester, fila('p1'));
      final nodo = tester.getSemantics(fila('p1'));
      expect(nodo.flagsCollection.isButton, isTrue);
      expect(nodo.flagsCollection.isEnabled, Tristate.isTrue);
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(nodo.label, contains('ENTREGA PENDIENTE'));
      expect(nodo.label, endsWith('Entregar'));
      semantica.dispose();
    });

    testWidgets('sin destino la tarjeta no es botón ni dice «Entregar»', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, mundo([pendiente('p1')], conDestino: false));
      await aVista(tester, fila('p1'));
      final nodo = tester.getSemantics(fila('p1'));
      expect(nodo.flagsCollection.isButton, isFalse);
      expect(nodo.label, isNot(contains('Entregar')));
      semantica.dispose();
    });

    testWidgets('con otra acción abriéndose la otra tarjeta queda deshabilitada y luego vuelve', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final m = mundo([pendiente('p1'), pendiente('p2', ventaId: 'ven-2')])
        ..compuertaEntrega = Completer<void>();
      await montarFicha(tester, m, lector: true);
      await aVista(tester, entregar('p1'));
      await tester.tap(entregar('p1'));
      await tester.pump();
      await aVista(tester, fila('p2'));
      final nodo = tester.getSemantics(fila('p2'));
      expect(nodo.flagsCollection.isEnabled, Tristate.isFalse);
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      m.compuertaEntrega!.complete();
      await asentar(tester);
      await aVista(tester, fila('p2'));
      expect(tester.getSemantics(fila('p2')).flagsCollection.isEnabled, Tristate.isTrue);
      semantica.dispose();
    });
  });

  group('casos límite', () {
    testWidgets('con el aviso de falla a la vista (360×640, 2,0×) se puede reintentar', (
      tester,
    ) async {
      final m = mundo([pendiente('p1')])..lanzarAlRegistrarEntrega = StateError('x');
      await montarFicha(tester, m, tamano: const Size(360, 640), escala: 2);
      await aVista(tester, entregar('p1'));
      await tester.tap(entregar('p1'));
      await asentar(tester);
      expect(find.text(TextosFicha.noPudimosAbrir), findsOneWidget);
      sinExcepcion(tester, 'aviso de falla');
      await aVista(tester, fila('p1'));
      await tester.tapAt(tester.getRect(fila('p1')).topLeft + const Offset(6, 6));
      await asentar(tester);
      expect(m.entregas, hasLength(2), reason: 'el segundo intento llegó al destino');
    });

    testWidgets('si falla dos veces seguidas no queda nada trabado', (tester) async {
      final m = mundo([pendiente('p1')])..lanzarAlRegistrarEntrega = StateError('1');
      await montarFicha(tester, m);
      await aVista(tester, entregar('p1'));
      await tester.tap(entregar('p1'));
      await asentar(tester);
      m.lanzarAlRegistrarEntrega = StateError('2');
      await aVista(tester, entregar('p1'));
      await tester.tap(entregar('p1'));
      await asentar(tester);
      expect(m.entregas, hasLength(2));
      await aVista(tester, entregar('p1'));
      await tester.tap(entregar('p1'));
      await asentar(tester);
      expect(m.entregas, hasLength(3));
    });

    testWidgets('en el filtro «Entrega pendiente» a 360×640 2,0× «Entregar» anda y no desborda', (
      tester,
    ) async {
      final m = mundo([pendiente('p1'), pendiente('p2', ventaId: 'ven-2')]);
      await montarFicha(tester, m, tamano: const Size(360, 640), escala: 2);
      final chip = find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente));
      await aVista(tester, chip);
      await tester.tap(chip);
      await asentar(tester);
      await aVista(tester, entregar('p2'));
      await tester.tap(entregar('p2'));
      await asentar(tester);
      expect(m.entregas.map((c) => c.ventaId), ['ven-2']);
      sinExcepcion(tester, 'filtro');
    });

    testWidgets('el mismo «Entregar» tocado dos veces mientras abre llega una sola vez', (
      tester,
    ) async {
      final m = mundo([pendiente('p1')])..compuertaEntrega = Completer<void>();
      await montarFicha(tester, m);
      await aVista(tester, entregar('p1'));
      await tester.tap(entregar('p1'));
      await tester.pump();
      await tester.tap(entregar('p1'), warnIfMissed: false);
      await tester.pump();
      expect(m.entregas, hasLength(1));
      m.compuertaEntrega!.complete();
      await asentar(tester);
      expect(m.entregas, hasLength(1));
    });

    testWidgets('el toString de la entrega no vuelca el nombre del producto', (tester) async {
      expect(pendiente('p1').toString(), isNot(contains('Nuestros')));
    });
  });
}

// HU-VEN-005 (#429): «Entregar» en la tarjeta de una entrega pendiente del historial (vista 32B·01).
// Lleva al mismo destino que «Registrar entrega» (`registrarEntregaDesdeLaFichaProvider`), ya en la
// venta de esa tarjeta. Sin destino, o con la ficha de solo lectura, la tarjeta no lo ofrece.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart'
    show ColoresAlta;
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

void main() {
  // El sábado 24/10/2026: la fecha prevista del canvas («SÁB 26/10» en 2024 cae acá un sábado 24).
  final prevista = DateTime(2026, 10, 24, 12);

  EntregaEnFicha pendiente(
    String id, {
    String ventaId = 'ven-1',
    String producto = 'Nuestros Hijos',
    int cantidad = 1,
  }) => EntregaEnFicha(
    id: id,
    fecha: prevista,
    pendiente: true,
    ventaId: ventaId,
    lineas: [LineaDeFicha(nombre: producto, cantidad: cantidad)],
  );

  /// El historial del canvas 32B·01 con una entrega pendiente de la venta 0042.
  List<MovimientoDeFicha> historial({List<MovimientoDeFicha> extra = const []}) => [
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

  MundoFicha mundo({
    List<MovimientoDeFicha>? movimientos,
    bool conDestino = true,
    MundoFicha? base,
  }) {
    final m = base ?? MundoFicha(historial: movimientos ?? historial(extra: [pendiente('ent-p1')]));
    m
      ..conRegistrarEntrega = conDestino
      ..cuentas.cuenta = cuentaConSaldo;
    return m;
  }

  const tamanoAlto = Size(390, 1800);

  Finder entregar(String id) => find.byKey(ClavesFicha.entregar(id));
  Finder fila(String id) => find.byKey(ClavesFicha.fila(id));

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await asentar(tester);
  }

  group('32B·01 · la tarjeta de la entrega pendiente', () {
    testWidgets(
      'dice cuándo está prevista, qué se entrega y ofrece «Entregar» en vez de la flecha',
      (tester) async {
        await montarFicha(tester, mundo(), tamano: tamanoAlto);

        final tarjeta = fila('ent-p1');
        expect(
          find.descendant(of: tarjeta, matching: find.text('SÁB 24/10 · ENTREGA PENDIENTE')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tarjeta, matching: find.text('Nuestros Hijos × 1')),
          findsOneWidget,
        );
        expect(entregar('ent-p1'), findsOneWidget);
        expect(find.text('Entregar'), findsOneWidget);
        expect(
          find.descendant(of: tarjeta, matching: find.byIcon(Icons.chevron_right)),
          findsNothing,
        );
      },
    );

    testWidgets('«Entregar» va a la derecha de la tarjeta, como en el canvas', (tester) async {
      await montarFicha(tester, mundo(), tamano: tamanoAlto);

      final caja = tester.getRect(fila('ent-p1'));
      final boton = tester.getRect(entregar('ent-p1'));
      expect(boton.right, lessThanOrEqualTo(caja.right));
      expect(boton.center.dx, greaterThan(caja.center.dx));
    });

    testWidgets('tocarla lleva al destino con la persona, el espacio y la venta de esa tarjeta', (
      tester,
    ) async {
      final m = mundo(
        movimientos: historial(extra: [pendiente('ent-p1', ventaId: 'ven-7')]),
      );
      await montarFicha(tester, m, tamano: tamanoAlto);

      await tocar(tester, entregar('ent-p1'));

      expect(m.entregas, [(personaId: 'per-1', espacioId: 'esp-1', ventaId: 'ven-7')]);
    });

    testWidgets('con dos pendientes de ventas distintas cada «Entregar» lleva su venta', (
      tester,
    ) async {
      final m = mundo(
        movimientos: historial(
          extra: [
            pendiente('ent-p1', ventaId: 'ven-1'),
            pendiente('ent-p2', ventaId: 'ven-2', producto: 'Salud y Hogar'),
          ],
        ),
      );
      await montarFicha(tester, m, tamano: tamanoAlto);

      await tocar(tester, entregar('ent-p2'));
      await tocar(tester, entregar('ent-p1'));

      expect(m.entregas.map((c) => c.ventaId), ['ven-2', 'ven-1']);
    });

    testWidgets('una pendiente sin venta conocida llega sin ella y el destino pregunta cuál', (
      tester,
    ) async {
      final sinVenta = EntregaEnFicha(
        id: 'ent-p1',
        fecha: prevista,
        pendiente: true,
        lineas: const [LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1)],
      );
      final m = mundo(movimientos: historial(extra: [sinVenta]));
      await montarFicha(tester, m, tamano: tamanoAlto);

      await tocar(tester, entregar('ent-p1'));

      expect(m.entregas.single.ventaId, isNull);
    });

    testWidgets('la tarjeta se anuncia como botón con «Entregar» y mide al menos 48 dp', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, mundo(), tamano: tamanoAlto);

      final nodo = tester.getSemantics(fila('ent-p1'));
      expect(nodo.label, contains('ENTREGA PENDIENTE'));
      expect(nodo.label, contains('Nuestros Hijos × 1'));
      expect(nodo.label, endsWith('Entregar'));
      expect(nodo.flagsCollection.isButton, isTrue);
      expect(tester.getSize(fila('ent-p1')).height, greaterThanOrEqualTo(48));
      semantica.dispose();
    });

    testWidgets('las demás tarjetas no cambian: la venta sigue sin «Entregar»', (tester) async {
      final m = mundo()..conDevolucion = true;
      await montarFicha(tester, m, tamano: tamanoAlto);

      expect(find.text('Entregar'), findsOneWidget);
      expect(
        find.descendant(of: fila('ven-1'), matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
    });
  });

  group('32B·03 · el filtro «Entrega pendiente»', () {
    testWidgets('deja solo las pendientes y cada una conserva su «Entregar»', (tester) async {
      final m = mundo(
        movimientos: historial(
          extra: [
            pendiente('ent-p1'),
            pendiente('ent-p2', producto: 'Salud y Hogar'),
          ],
        ),
      );
      await montarFicha(tester, m, tamano: tamanoAlto);

      await tocar(tester, find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente)));

      expect(fila('ent-p1'), findsOneWidget);
      expect(fila('ent-p2'), findsOneWidget);
      expect(fila('ven-1'), findsNothing);
      expect(find.text('Entregar'), findsNWidgets(2));
    });

    testWidgets('sin pendientes en el historial dice que no hay y no ofrece «Entregar»', (
      tester,
    ) async {
      final m = mundo(movimientos: historial());
      await montarFicha(tester, m, tamano: tamanoAlto);

      await tocar(tester, find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente)));

      expect(find.byKey(ClavesFicha.sinResultados), findsOneWidget);
      expect(find.text('Entregar'), findsNothing);
    });
  });

  group('sin destino y solo lectura (32B·04 y 32B·08)', () {
    testWidgets('sin destino la tarjeta queda como estaba, sin «Entregar» ni toque', (
      tester,
    ) async {
      await montarFicha(tester, mundo(conDestino: false), tamano: tamanoAlto);

      expect(fila('ent-p1'), findsOneWidget);
      expect(find.text('Entregar'), findsNothing);
      expect(find.descendant(of: fila('ent-p1'), matching: find.byType(InkWell)), findsNothing);
    });

    testWidgets('con la persona de baja no se ofrece «Entregar»', (tester) async {
      final m = MundoFicha(
        persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
        historial: historial(extra: [pendiente('ent-p1')]),
        notasIniciales: notasDeLaFicha(),
        contexto: contextoBajaDesde22(),
      );
      await montarFicha(tester, mundo(base: m), tamano: tamanoAlto);

      expect(fila('ent-p1'), findsOneWidget);
      expect(find.text('Entregar'), findsNothing);
    });

    testWidgets('con el depto de baja no se ofrece «Entregar»', (tester) async {
      final m = MundoFicha(
        historial: historial(extra: [pendiente('ent-p1')]),
        notasIniciales: notasDeLaFicha(),
        contexto: contextoDeptoDeBaja,
      );
      await montarFicha(tester, mundo(base: m), tamano: tamanoAlto);

      expect(fila('ent-p1'), findsOneWidget);
      expect(find.text('Entregar'), findsNothing);
    });
  });

  group('casos límite', () {
    testWidgets('un doble toque abre el destino una sola vez', (tester) async {
      final m = mundo()..compuertaEntrega = Completer<void>();
      await montarFicha(tester, m, tamano: tamanoAlto);
      await tester.ensureVisible(entregar('ent-p1'));
      await tester.pump();

      await tester.tap(entregar('ent-p1'));
      await tester.tap(entregar('ent-p1'), warnIfMissed: false);
      await tester.pump();

      expect(m.entregas, hasLength(1));

      m.compuertaEntrega!.complete();
      await asentar(tester);
      // Ya volvió: se puede abrir otra vez.
      await tester.tap(entregar('ent-p1'));
      await asentar(tester);
      expect(m.entregas, hasLength(2));
    });

    testWidgets('si el destino falla a mitad avisa qué hacer y «Entregar» vuelve a andar', (
      tester,
    ) async {
      final m = mundo()..lanzarAlRegistrarEntrega = StateError('no abrió');
      await montarFicha(tester, m, tamano: tamanoAlto);

      await tocar(tester, entregar('ent-p1'));

      expect(find.text(TextosFicha.noPudimosAbrir), findsOneWidget);
      // Nada quedó trabado: ni el chip ni la tarjeta están apagados.
      expect(
        tester.widget<ActionChip>(find.byKey(ClavesFicha.botonRegistrarEntrega)).onPressed,
        isNotNull,
      );
      final texto = tester.widget<Text>(entregar('ent-p1'));
      expect(texto.style?.color, isNot(ColoresAlta.gris));

      await tester.tap(entregar('ent-p1'));
      await asentar(tester);
      expect(m.entregas, hasLength(2));
    });

    testWidgets(
      'con una entrega abriéndose, el chip y las otras tarjetas se apagan sin perder nada',
      (tester) async {
        final m = mundo(
          movimientos: historial(
            extra: [
              pendiente('ent-p1', ventaId: 'ven-1'),
              pendiente('ent-p2', ventaId: 'ven-2', producto: 'Salud y Hogar'),
            ],
          ),
        )..compuertaEntrega = Completer<void>();
        await montarFicha(tester, m, tamano: tamanoAlto);
        await tester.ensureVisible(entregar('ent-p1'));
        await tester.pump();

        await tester.tap(entregar('ent-p1'));
        await tester.pump();

        // La primera sigue abriéndose: la segunda tarjeta y el chip no responden.
        expect(
          tester.widget<ActionChip>(find.byKey(ClavesFicha.botonRegistrarEntrega)).onPressed,
          isNull,
        );
        expect(tester.widget<Text>(entregar('ent-p2')).style?.color, ColoresAlta.gris);
        await tester.ensureVisible(entregar('ent-p2'));
        await tester.pump();
        await tester.tap(entregar('ent-p2'), warnIfMissed: false);
        await tester.pump();
        expect(m.entregas.map((c) => c.ventaId), ['ven-1']);

        m.compuertaEntrega!.complete();
        await asentar(tester);

        // Ya sin la primera, la segunda anda: no se pisó ni se perdió ninguna.
        await tocar(tester, entregar('ent-p2'));
        expect(m.entregas.map((c) => c.ventaId), ['ven-1', 'ven-2']);
      },
    );

    testWidgets('al volver atrás y reentrar la tarjeta sigue con «Entregar» y tocable', (
      tester,
    ) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: tamanoAlto);
      await tocar(tester, entregar('ent-p1'));
      expect(m.entregas, hasLength(1));

      await volverAtras(tester);
      await tester.tap(find.text('abrir ficha'));
      await asentar(tester);

      expect(entregar('ent-p1'), findsOneWidget);
      await tocar(tester, entregar('ent-p1'));
      expect(m.entregas, hasLength(2));
    });

    testWidgets('al entregar lo pendiente la ficha, que lee en vivo, deja de mostrarla', (
      tester,
    ) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: tamanoAlto);
      expect(entregar('ent-p1'), findsOneWidget);

      // El destino marcó la entrega como hecha: la lectura ya no trae la pendiente.
      m.fichas.poner(LecturaDeFicha(persona: mariaDePrueba(), historial: historial()));
      await asentar(tester);

      expect(fila('ent-p1'), findsNothing);
      expect(find.text('Entregar'), findsNothing);
    });

    for (final escala in [1.0, 1.5, 2.0]) {
      testWidgets(
        'con letra al ${(escala * 100).round()} % en 320 × 568 la tarjeta no desborda y se llega a «Entregar»',
        (tester) async {
          final m = mundo(
            movimientos: historial(
              extra: [
                pendiente('ent-p1', producto: 'Salud y Hogar y Nuestros Hijos Edición Ampliada'),
              ],
            ),
          );
          await montarFicha(tester, m, escala: escala, tamano: const Size(320, 568));
          final lista = find.byType(Scrollable).first;
          await tester.scrollUntilVisible(entregar('ent-p1'), 300, scrollable: lista);
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(tester.getSize(fila('ent-p1')).height, greaterThanOrEqualTo(48));
          await tester.tap(entregar('ent-p1'));
          await asentar(tester);
          expect(m.entregas, hasLength(1));
        },
      );
    }

    testWidgets('con 40 pendientes cada «Entregar» lleva la venta de la suya', (tester) async {
      final pendientes = [
        for (var i = 0; i < 40; i++) pendiente('ent-p$i', ventaId: 'ven-$i', cantidad: i + 1),
      ];
      final m = mundo(movimientos: historial(extra: pendientes));
      await montarFicha(tester, m, tamano: tamanoAlto);
      await tocar(tester, find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente)));

      expect(find.text('Entregar', skipOffstage: false), findsNWidgets(40));
      await tocar(tester, entregar('ent-p39'));

      expect(m.entregas.single.ventaId, 'ven-39');
    });
  });
}

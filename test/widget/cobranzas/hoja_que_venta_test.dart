// «¿Qué venta?» (vista 39, C·08, HU-COB-001, #440): el artboard C·08 y los estados de la HU (una sola
// venta se salta, cargando, sin saldo, error al leer), con los casos límite de la acción: doble toque,
// falla a mitad de la lectura, dos elecciones seguidas, volver atrás y reentrar, y datos límite (listas
// largas, textos largos y textScaler 2.0).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/hoja_que_venta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cobrar_desde_la_casa_arnes.dart';

Finder get _cobrar => find.byKey(ClavesQueVenta.cobrar);
Finder get _cancelar => find.byKey(ClavesQueVenta.cancelar);

VentaConSaldo _venta(int n, {String descripcion = 'Colección de 1 libro', int saldo = 50000}) =>
    VentaConSaldo(
      ventaId: 'v-$n',
      numeroTalonario: n.toString().padLeft(4, '0'),
      fecha: DateTime.utc(2026, 10, 1 + (n % 27), 15),
      montoTotalCentavos: saldo,
      cobradoCentavos: 0,
      descripcion: descripcion,
    );

void main() {
  group('C·08 · Cobrar: ¿qué venta?', () {
    testWidgets(
      'dado el canvas, cuando hay dos ventas con saldo, entonces las dibuja como el diseño',
      (tester) async {
        await montarQueVenta(
          tester,
          repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
        );

        expect(find.text('¿Qué le cobrás a Pedro?'), findsOneWidget);
        expect(find.text('Venta 0038 · 12/10'), findsOneWidget);
        expect(find.text('Colección de 1 libro'), findsOneWidget);
        expect(find.text(r'$ 1.200'), findsOneWidget);
        expect(find.text('Venta 0045 · 20/10'), findsOneWidget);
        expect(find.text('Vida Feliz × 2'), findsOneWidget);
        expect(find.text(r'$ 240'), findsOneWidget);
        expect(find.text('Cobrar'), findsOneWidget);
        expect(find.text('Cancelar'), findsOneWidget);
      },
    );

    testWidgets('viene elegida la más vieja y «Cobrar» devuelve esa venta', (tester) async {
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      await tocarQueVenta(tester, _cobrar);

      expect(r.elegida?.ventaId, 'v-38');
      expect(r.cierres, 1);
      expect(find.byKey(ClavesQueVenta.lista), findsNothing);
    });

    testWidgets('tocar otra venta la elige, y «Cobrar» devuelve esa', (tester) async {
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.fila('v-45')));
      await tocarQueVenta(tester, _cobrar);

      expect(r.elegida?.ventaId, 'v-45');
    });

    testWidgets('«Cancelar» cierra sin elegir nada', (tester) async {
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      await tocarQueVenta(tester, _cancelar);

      expect(r.elegida, isNull);
      expect(r.cierres, 1);
      expect(r.abiertas, 0);
    });

    testWidgets('la elegida se lee al lector de pantalla con su saldo y sin repetir', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      expect(
        find.bySemanticsLabel(r'Venta 0038 · 12/10. Colección de 1 libro. Saldo $ 1.200'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(ClavesQueVenta.fila('v-38'))),
        matchesSemantics(
          label: r'Venta 0038 · 12/10. Colección de 1 libro. Saldo $ 1.200',
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      semantica.dispose();
    });

    testWidgets('sin nombre (la persona ya no está en la casa), pregunta sin él', (tester) async {
      await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
        nombre: null,
      );

      expect(find.text('¿Qué venta cobrás?'), findsOneWidget);
    });
  });

  group('Una sola venta con saldo: se salta', () {
    testWidgets(
      'dado una venta, cuando se pide la hoja, entonces no se abre y devuelve esa venta',
      (tester) async {
        final repo = cobranzasConVentas([ventaDelCanvas38()]);
        final r = await montarQueVenta(tester, repo: repo);

        expect(r.elegida?.ventaId, 'v-38');
        expect(r.cierres, 1);
        // Solo la hoja de arranque: ninguna ruta se abrió encima.
        expect(r.rutas.aperturas, 1);
        expect(find.text('¿Qué le cobrás a Pedro?'), findsNothing);
      },
    );

    testWidgets('una venta ya pagada no cuenta: la otra se salta igual', (tester) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..fija = [ventaDelCanvas38(), ventaDelCanvas45(saldo: 0)];
      final r = await montarQueVenta(tester, repo: repo);

      expect(r.elegida?.ventaId, 'v-38');
      expect(r.rutas.aperturas, 1);
    });

    testWidgets('si la lectura tarda, la hoja espera cargando y se cierra sola con esa venta', (
      tester,
    ) async {
      final repo = cobranzasConVentas([ventaDelCanvas38()])..compuerta = Completer<void>();
      final r = await montarQueVenta(tester, repo: repo);

      expect(find.byKey(ClavesQueVenta.cargando), findsOneWidget);
      expect(find.text('Cargando las ventas…'), findsOneWidget);

      repo.compuerta!.complete();
      await asentarLuego(tester);

      expect(r.elegida?.ventaId, 'v-38');
      expect(r.cierres, 1);
      expect(r.abiertas, 0);
    });
  });

  group('Cargando', () {
    testWidgets('mientras lee dice qué espera y deja cancelar', (tester) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..compuerta = Completer<void>();
      final r = await montarQueVenta(tester, repo: repo);

      expect(find.text('Cargando las ventas…'), findsOneWidget);
      expect(_cobrar, findsNothing);

      await tocarQueVenta(tester, _cancelar);

      expect(r.elegida, isNull);
      expect(r.abiertas, 0);
      // La lectura que llegue tarde no encuentra la hoja: no rompe nada.
      repo.compuerta!.complete();
      await asentarLuego(tester);
    });

    testWidgets('cuando llega la lista, pasa a C·08 sin dejar el cargando trabado', (tester) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..compuerta = Completer<void>();
      await montarQueVenta(tester, repo: repo);

      repo.compuerta!.complete();
      await asentarLuego(tester);

      expect(find.byKey(ClavesQueVenta.cargando), findsNothing);
      expect(_cobrar, findsOneWidget);
    });
  });

  group('Sin ventas con saldo', () {
    testWidgets('lo dice con el nombre y «Cerrar» cierra sin elegir', (tester) async {
      final repo = cobranzasConVentas([])..fija = const [];
      final r = await montarQueVenta(tester, repo: repo);

      expect(
        find.text('Pedro no tiene ventas con saldo. No queda nada para cobrar.'),
        findsOneWidget,
      );
      expect(_cobrar, findsNothing);

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cerrar));

      expect(r.elegida, isNull);
      expect(r.abiertas, 0);
    });

    testWidgets('sin nombre, lo dice sin él', (tester) async {
      final repo = cobranzasConVentas([])..fija = const [];
      await montarQueVenta(tester, repo: repo, nombre: null);

      expect(find.text('No hay ventas con saldo. No queda nada para cobrar.'), findsOneWidget);
    });
  });

  group('Error al leer las ventas', () {
    testWidgets('una falla dice qué pasó y «Reintentar» lee de nuevo y llega a C·08', (
      tester,
    ) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..fallas.add(const FailureInesperado(causa: 'x'));
      await montarQueVenta(tester, repo: repo);

      expect(find.text('No pudimos leer las ventas guardadas en tu teléfono.'), findsOneWidget);
      expect(find.byKey(ClavesQueVenta.reintentar), findsOneWidget);
      expect(_cancelar, findsOneWidget);
      expect(_cobrar, findsNothing);

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.reintentar));

      expect(find.byKey(ClavesQueVenta.error), findsNothing);
      expect(_cobrar, findsOneWidget);
    });

    testWidgets('una excepción se trata igual y no se escapa', (tester) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..fallas.add(StateError('no se pudo leer'));
      await montarQueVenta(tester, repo: repo);

      expect(find.text('No pudimos leer las ventas guardadas en tu teléfono.'), findsOneWidget);
    });

    testWidgets('«Reintentar» que vuelve a fallar deja el aviso y la acción habilitada', (
      tester,
    ) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..fallas.addAll([const FailureInesperado(causa: 'a'), const FailureInesperado(causa: 'b')]);
      await montarQueVenta(tester, repo: repo);

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.reintentar));

      expect(find.byKey(ClavesQueVenta.error), findsOneWidget);
      expect(find.byKey(ClavesQueVenta.cargando), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(ClavesQueVenta.reintentar)).onPressed,
        isNotNull,
      );

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.reintentar));

      expect(_cobrar, findsOneWidget);
    });

    testWidgets('con un solo venta después de reintentar, se salta', (tester) async {
      final repo = cobranzasConVentas([ventaDelCanvas38()])
        ..fallas.add(const FailureInesperado(causa: 'x'));
      final r = await montarQueVenta(tester, repo: repo);

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.reintentar));

      expect(r.elegida?.ventaId, 'v-38');
      expect(r.abiertas, 0);
    });

    testWidgets('dos «Reintentar» seguidos leen una sola vez', (tester) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..fallas.add(const FailureInesperado(causa: 'x'));
      await montarQueVenta(tester, repo: repo);
      final antes = repo.lecturas;
      repo.compuerta = Completer<void>();

      final boton = find.byKey(ClavesQueVenta.reintentar);
      await tester.tap(boton);
      await tester.tap(boton, warnIfMissed: false);
      await asentarLuego(tester);
      repo.compuerta!.complete();
      await asentarLuego(tester);

      expect(repo.lecturas - antes, 1);
    });
  });

  group('Casos límite de la acción', () {
    testWidgets('doble toque en «Cobrar»: se cierra una vez y devuelve una venta', (tester) async {
      final semantica = tester.ensureSemantics();
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      // Dos toques por la semántica, sin cuadro en el medio: la ruta que se cierra ignora los toques
      // de puntero, así que solo así el segundo llega a la acción.
      final boton = find.semantics.byLabel('Cobrar');
      tester.semantics.performAction(boton, SemanticsAction.tap);
      tester.semantics.performAction(boton, SemanticsAction.tap);
      await asentarLuego(tester);

      expect(r.cierres, 1);
      expect(r.elegida?.ventaId, 'v-38');
      expect(r.rutas.cierres, 1);
      semantica.dispose();
    });

    testWidgets('doble toque en «Cancelar»: se cierra una vez', (tester) async {
      final semantica = tester.ensureSemantics();
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      final boton = find.semantics.byLabel('Cancelar');
      tester.semantics.performAction(boton, SemanticsAction.tap);
      tester.semantics.performAction(boton, SemanticsAction.tap);
      await asentarLuego(tester);

      expect(r.cierres, 1);
      expect(r.rutas.cierres, 1);
      semantica.dispose();
    });

    testWidgets('dos elecciones seguidas antes de «Cobrar»: gana la última', (tester) async {
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      await tester.tap(find.byKey(ClavesQueVenta.fila('v-45')));
      await tester.tap(find.byKey(ClavesQueVenta.fila('v-38')));
      await tester.pump();
      await tocarQueVenta(tester, _cobrar);

      expect(r.elegida?.ventaId, 'v-38');
    });

    testWidgets('elegir y «Cobrar» sin pausa entrega la elegida y no la anterior', (tester) async {
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      await tester.tap(find.byKey(ClavesQueVenta.fila('v-45')));
      await tester.tap(_cobrar);
      await asentarLuego(tester);

      expect(r.elegida?.ventaId, 'v-45');
    });

    testWidgets('volver atrás y reentrar: la hoja arranca de nuevo con la más vieja elegida', (
      tester,
    ) async {
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );
      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.fila('v-45')));
      await tocarQueVenta(tester, _cancelar);
      expect(r.elegida, isNull);

      await abrirQueVenta(tester);
      await tocarQueVenta(tester, _cobrar);

      expect(r.elegida?.ventaId, 'v-38');
      expect(r.cierres, 2);
    });

    testWidgets('con el botón atrás del sistema cierra sin elegir', (tester) async {
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      await tester.binding.handlePopRoute();
      await asentarLuego(tester);

      expect(r.elegida, isNull);
      expect(r.cierres, 1);
    });

    testWidgets('la venta se paga mientras la hoja está abierta: lo que se lee de nuevo manda', (
      tester,
    ) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..fallas.add(const FailureInesperado(causa: 'x'));
      await montarQueVenta(tester, repo: repo);
      repo.fija = [ventaDelCanvas38(), ventaDelCanvas45(saldo: 0)];

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.reintentar));

      // Quedó una sola con saldo: el paso de elegir se salta.
      expect(find.byKey(ClavesQueVenta.lista), findsNothing);
    });
  });

  group('Datos límite', () {
    testWidgets('una lista larga se desplaza, la última se elige y «Cobrar» queda a la vista', (
      tester,
    ) async {
      final ventas = [for (var i = 1; i <= 40; i++) _venta(i)];
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas(ventas),
        tamano: const Size(320, 568),
      );

      expect(_cobrar, findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(ClavesQueVenta.fila('v-40')),
        200,
        scrollable: find.descendant(
          of: find.byKey(ClavesQueVenta.lista),
          matching: find.byType(Scrollable),
        ),
      );
      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.fila('v-40')));
      expect(tester.getRect(_cobrar).bottom, lessThanOrEqualTo(568));
      await tocarQueVenta(tester, _cobrar);

      expect(r.elegida?.ventaId, 'v-40');
    });

    testWidgets('textos largos y textScaler 2.0 en 320×568 no desbordan y se puede cobrar', (
      tester,
    ) async {
      final larga = 'Colección Salud y Hogar · ' * 6;
      final r = await montarQueVenta(
        tester,
        repo: cobranzasConVentas([
          _venta(1, descripcion: larga, saldo: 123456789),
          _venta(2, descripcion: larga),
        ]),
        nombre: 'Maximiliano Alejandro de los Ángeles',
        escala: 2,
        tamano: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      expect(_cobrar, findsOneWidget);
      expect(_cancelar, findsOneWidget);
      await tocarQueVenta(tester, _cobrar);

      expect(r.elegida?.ventaId, 'v-1');
    });

    testWidgets(
      'textScaler 2.0: el error de lectura mantiene «Reintentar» y «Cancelar» a la mano',
      (tester) async {
        final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
          ..fallas.add(const FailureInesperado(causa: 'x'));
        await montarQueVenta(tester, repo: repo, escala: 2, tamano: const Size(320, 568));

        expect(tester.takeException(), isNull);
        expect(find.byKey(ClavesQueVenta.reintentar), findsOneWidget);
        await tester.ensureVisible(_cancelar);
        expect(_cancelar, findsOneWidget);
      },
    );

    testWidgets('textScaler 2.0: «sin saldo» entra en la pantalla', (tester) async {
      final sin = cobranzasConVentas([])..fija = const [];
      await montarQueVenta(tester, repo: sin, escala: 2, tamano: const Size(320, 568));
      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesQueVenta.sinSaldo), findsOneWidget);
    });

    testWidgets('con el lector activo las filas siguen siendo opciones excluyentes', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarQueVenta(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
        lector: true,
      );

      expect(
        tester.getSemantics(find.byKey(ClavesQueVenta.fila('v-45'))),
        matchesSemantics(
          label: r'Venta 0045 · 20/10. Vida Feliz × 2. Saldo $ 240',
          hasCheckedState: true,
          isChecked: false,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      semantica.dispose();
    });
  });
}

/// Deja correr los fotogramas que hacen falta después de completar una compuerta o cerrar una hoja.
Future<void> asentarLuego(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

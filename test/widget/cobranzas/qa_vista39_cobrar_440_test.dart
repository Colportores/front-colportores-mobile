// QA de «$ Cobrar» desde la casa (vista 39, C·08 «¿Qué venta?», HU-COB-001, #440). Lo que no cubren los
// tests del PR: los 11 estados × 360x640 y 412x915 × texto 1,0 y 2,0 (sin desborde, sin texto cortado,
// con el pie a la vista y captura), los textos literales del canvas, los casos límite (cancelar o
// cerrar mientras lee, cambio de tamaño con la hoja abierta, la venta que se paga antes de tocar
// «Cobrar», atrás desde el cobro) y la privacidad.
// Las capturas solo con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas`).
// Los hallazgos van con `skip` y el motivo; `--dart-define=QA_HALLAZGOS=true` los corre.
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/domain/value_objects/paso_que_venta.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/hoja_que_venta.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/cobrar_desde_la_casa_arnes.dart';
import '../../helpers/cobro_arnes.dart' show cobroDeEjemplo, pagina, cerrarCobro;
import '../../helpers/qa_vista39_440_arnes.dart';

Finder get _cobrar => find.byKey(ClavesQueVenta.cobrar);
Finder get _cancelar => find.byKey(ClavesQueVenta.cancelar);
Finder get _reintentar => find.byKey(ClavesQueVenta.reintentar);
Finder get _cerrar => find.byKey(ClavesQueVenta.cerrar);

/// Lo que se ve de la hoja cabe en la pantalla, sin tener que desplazarla.
void _dentroDeLaPantalla(WidgetTester tester, Finder f, Size tamano, String que) {
  if (f.evaluate().isEmpty) return;
  final r = tester.getRect(f.first);
  expect(r.top, greaterThanOrEqualTo(0), reason: '$que arriba de la pantalla');
  expect(r.bottom, lessThanOrEqualTo(tamano.height + 0.5), reason: '$que bajo el pliegue');
}

void main() {
  group('Matriz: cada estado × tamaño × escala de texto', () {
    for (final tamano in [chico440, grande440]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado440.values) {
          testWidgets(
            '${estado.rotulo} · ${sufijo440(tamano, escala)}: sin desborde ni texto cortado, '
            'con las acciones a la vista',
            (tester) async {
              final m = await llegarA440(tester, estado, tamano: tamano, escala: escala);

              expect(tester.takeException(), isNull);
              sinTextoCortado440(tester);
              await capturar440(tester, '${estado.name}_${sufijo440(tamano, escala)}');
              // El pie de la hoja (la acción que sigue) se ve sin desplazar nada.
              for (final (f, que) in [
                (_cobrar, '«Cobrar»'),
                (_cancelar, '«Cancelar»'),
                (_reintentar, '«Reintentar»'),
                (_cerrar, '«Cerrar»'),
              ]) {
                _dentroDeLaPantalla(tester, f, tamano, que);
              }
              await liberar440(tester, m);
            },
          );
        }
      }
    }
  });

  group('Canvas C·08: textos literales', () {
    testWidgets('«¿Qué le cobrás a Pedro?», las dos ventas con su monto, «Cobrar» y «Cancelar»', (
      tester,
    ) async {
      await llegarA440(tester, Estado440.c08Lista);

      expect(find.text('¿Qué le cobrás a Pedro?'), findsOneWidget);
      expect(find.text('Venta 0038 · 12/10'), findsOneWidget);
      expect(find.text('Colección de 1 libro'), findsOneWidget);
      expect(find.text(r'$ 1.200'), findsOneWidget);
      expect(find.text('Venta 0045 · 20/10'), findsOneWidget);
      expect(find.text('Vida Feliz × 2'), findsOneWidget);
      expect(find.text(r'$ 240'), findsOneWidget);
      expect(find.text('Cobrar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('la fecha de la venta es el día de Montevideo, no el de UTC', (tester) async {
      // 02:30 UTC del 13/10 son las 23:30 del 12/10 en Montevideo; las 01:00 UTC del 20/10, el 19/10.
      final repo = cobranzasConVentas([
        VentaConSaldo(
          ventaId: 'v-a',
          numeroTalonario: '0001',
          fecha: DateTime.utc(2026, 10, 13, 2, 30),
          montoTotalCentavos: 1000,
          cobradoCentavos: 0,
        ),
        VentaConSaldo(
          ventaId: 'v-b',
          numeroTalonario: '0002',
          fecha: DateTime.utc(2026, 10, 20, 1),
          montoTotalCentavos: 2000,
          cobradoCentavos: 0,
        ),
      ]);
      await montarQueVenta(tester, repo: repo);

      expect(find.text('Venta 0001 · 12/10'), findsOneWidget);
      expect(find.text('Venta 0002 · 19/10'), findsOneWidget);
    });

    testWidgets('un monto con centavos o de millones se escribe como el resto de la app', (
      tester,
    ) async {
      final repo = cobranzasConVentas(const [])
        ..fija = [
          VentaConSaldo(
            ventaId: 'v-a',
            numeroTalonario: '0001',
            fecha: DateTime.utc(2026, 10, 1, 15),
            montoTotalCentavos: 850050,
            cobradoCentavos: 0,
          ),
          VentaConSaldo(
            ventaId: 'v-b',
            numeroTalonario: '0002',
            fecha: DateTime.utc(2026, 10, 2, 15),
            montoTotalCentavos: 123456789,
            cobradoCentavos: 1,
          ),
        ];
      await montarQueVenta(tester, repo: repo);

      expect(find.text(r'$ 8.500,50'), findsOneWidget);
      expect(find.text(r'$ 1.234.567,88'), findsOneWidget);
    });

    testWidgets('«Cobrar» y «Cancelar» van en ese orden, «Cobrar» arriba', (tester) async {
      await llegarA440(tester, Estado440.c08Lista);

      expect(tester.getTopLeft(_cobrar).dy, lessThan(tester.getTopLeft(_cancelar).dy));
      expect(tester.getSize(_cobrar).height, greaterThanOrEqualTo(56));
      expect(tester.getSize(_cancelar).height, greaterThanOrEqualTo(56));
    });
  });

  group('Estados que el canvas no dibuja: cada uno dice qué pasa y qué hacer', () {
    testWidgets('cargando: dice qué espera, es región viva y deja cancelar', (tester) async {
      final h = tester.ensureSemantics();
      final m = await llegarA440(tester, Estado440.cargando);

      expect(find.text('Cargando las ventas…'), findsOneWidget);
      expect(_cancelar, findsOneWidget);
      var viva = false;
      void ver(SemanticsNode n) {
        if (n.flagsCollection.isLiveRegion && n.label.contains('Cargando')) viva = true;
        n.visitChildren((c) {
          ver(c);
          return true;
        });
      }

      ver(tester.getSemantics(find.byKey(ClavesQueVenta.cargando)));
      expect(viva, isTrue);
      await liberar440(tester, m);
      h.dispose();
    });

    testWidgets('error de lectura: el aviso es región viva y «Reintentar» y «Cancelar» salen', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarA440(tester, Estado440.errorLectura);

      expect(find.text('No pudimos leer las ventas guardadas en tu teléfono.'), findsOneWidget);
      expect(_reintentar, findsOneWidget);
      expect(_cancelar, findsOneWidget);
      var viva = false;
      void ver(SemanticsNode n) {
        if (n.flagsCollection.isLiveRegion) viva = true;
        n.visitChildren((c) {
          ver(c);
          return true;
        });
      }

      ver(tester.getSemantics(find.byKey(ClavesQueVenta.error)));
      expect(viva, isTrue, reason: 'el error se anuncia solo');
      h.dispose();
    });

    testWidgets('sin saldo: lo dice con el nombre y «Cerrar» devuelve nada', (tester) async {
      final h = tester.ensureSemantics();
      final m = await llegarA440(tester, Estado440.sinSaldo);

      expect(
        find.text('Pedro no tiene ventas con saldo. No queda nada para cobrar.'),
        findsOneWidget,
      );
      expect(_cobrar, findsNothing, reason: 'no hay nada que cobrar: sin «Cobrar»');
      await tocarQueVenta(tester, _cerrar);
      expect(m.resultado.cierres, 1);
      expect(m.resultado.elegida, isNull);
      h.dispose();
    });

    testWidgets('sin nombre y sin saldo: la frase no deja un hueco', (tester) async {
      await llegarA440(tester, Estado440.sinSaldoSinNombre);

      expect(find.text('No hay ventas con saldo. No queda nada para cobrar.'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('  '), findsNothing);
    });

    testWidgets('una venta sin descripción no deja una línea vacía ni la palabra «null»', (
      tester,
    ) async {
      await llegarA440(tester, Estado440.c08SinDescripcion);

      expect(find.text('Venta 0077 · 22/10'), findsOneWidget);
      expect(find.text(r'$ 400'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('error dos veces seguidas: el aviso sigue, «Reintentar» sigue habilitado', (
      tester,
    ) async {
      await llegarA440(tester, Estado440.errorLecturaTrasReintento);

      expect(find.text('No pudimos leer las ventas guardadas en tu teléfono.'), findsOneWidget);
      expect(tester.widget<FilledButton>(_reintentar).onPressed, isNotNull);
      expect(find.text('Cargando las ventas…'), findsNothing, reason: 'nada quedó trabado');
    });

    testWidgets('tras dos errores, el tercer «Reintentar» lee bien y llega a C·08', (tester) async {
      final m = await llegarA440(tester, Estado440.errorLecturaTrasReintento);

      await tocarQueVenta(tester, _reintentar);

      expect(find.text('¿Qué le cobrás a Pedro?'), findsOneWidget);
      expect(m.repo.lecturas, 3);
      expect(tester.widget<FilledButton>(_cobrar).onPressed, isNotNull);
    });
  });

  group('Casos límite de la hoja', () {
    testWidgets('«Cancelar» mientras lee y después llega la lectura: nada se rompe ni se reabre', (
      tester,
    ) async {
      final m = await llegarA440(tester, Estado440.cargando);

      await tocarQueVenta(tester, _cancelar);
      expect(m.resultado.cierres, 1);
      m.repo.compuerta!.complete();
      await asentarAgendar(tester);

      expect(tester.takeException(), isNull);
      expect(m.resultado.cierres, 1);
      expect(m.resultado.elegida, isNull);
      expect(m.resultado.abiertas, 0);
      expect(find.byType(HojaQueVenta), findsNothing);
    });

    testWidgets('tocar fuera de la hoja mientras lee la cierra sin elegir y no deja nada colgado', (
      tester,
    ) async {
      final m = await llegarA440(tester, Estado440.cargando);

      await tester.tapAt(const Offset(180, 12));
      await asentarAgendar(tester);
      m.repo.compuerta!.complete();
      await asentarAgendar(tester);

      expect(tester.takeException(), isNull);
      expect(m.resultado.cierres, 1);
      expect(m.resultado.elegida, isNull);
      expect(find.byType(HojaQueVenta), findsNothing);
    });

    for (final estado in [
      Estado440.cargando,
      Estado440.errorLectura,
      Estado440.sinSaldo,
      Estado440.c08SegundaElegida,
    ]) {
      testWidgets('atrás del sistema en «${estado.rotulo}» cierra sin elegir ni cobrar', (
        tester,
      ) async {
        final m = await llegarA440(tester, estado);

        await tester.binding.handlePopRoute();
        await asentarAgendar(tester);
        await liberar440(tester, m);

        expect(m.resultado.cierres, 1);
        expect(m.resultado.elegida, isNull);
        expect(find.byType(HojaQueVenta), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('con la lista abierta, tocar fuera cierra sin elegir', (tester) async {
      final m = await llegarA440(tester, Estado440.c08SegundaElegida);

      await tester.tapAt(const Offset(180, 8));
      await asentarAgendar(tester);

      expect(m.resultado.cierres, 1);
      expect(m.resultado.elegida, isNull, reason: 'cerrar no es cobrar la elegida');
    });

    testWidgets('la lectura que llega con una sola venta mientras se mira «cargando» salta sola', (
      tester,
    ) async {
      final m = await llegarA440(tester, Estado440.cargando);
      m.repo.fija = [ventaDelCanvas45()];

      m.repo.compuerta!.complete();
      await asentarAgendar(tester);

      expect(m.resultado.elegida?.ventaId, 'v-45');
      expect(m.resultado.cierres, 1);
    });

    testWidgets('cambiar el tamaño de la pantalla con la hoja abierta no rompe nada', (
      tester,
    ) async {
      await llegarA440(tester, Estado440.c08SegundaElegida);

      tester.view.physicalSize = grande440;
      await tester.pump();
      tester.view.physicalSize = chico440;
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('¿Qué le cobrás a Pedro?'), findsOneWidget);
      expect(
        (tester.widget<Material>(
          find.descendant(
            of: find.byKey(ClavesQueVenta.fila('v-45')),
            matching: find.byType(Material),
          ),
        )).color,
        const Color(0xFFF2F6FB),
        reason: 'la elegida sigue siendo la segunda',
      );
    });

    testWidgets('14 ventas con textos largos: se llega a la última y «Cobrar» devuelve esa', (
      tester,
    ) async {
      final m = await llegarA440(tester, Estado440.c08Muchas, tamano: chico440, escala: 2);

      await tocarFilaQueVenta440(tester, 'v-m13');
      _dentroDeLaPantalla(tester, _cobrar, chico440, '«Cobrar»');
      await tester.tap(_cobrar);
      await asentarAgendar(tester);

      expect(m.resultado.elegida?.ventaId, 'v-m13');
      expect(tester.takeException(), isNull);
    });

    testWidgets('14 ventas: la hoja no se pasa de la altura de la pantalla', (tester) async {
      await llegarA440(tester, Estado440.c08Muchas, tamano: chico440, escala: 1);

      final hoja = tester.getRect(find.byType(HojaQueVenta));
      expect(hoja.height, lessThanOrEqualTo(chico440.height));
      expect(hoja.top, greaterThanOrEqualTo(0));
    });
  });

  group('Flujo entero: de «\$ Cobrar» al cobro', () {
    testWidgets(
      'lo que se paga en otro lado mientras se mira la lista: el cobro lo dice y deja salir',
      (tester) async {
        final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]);
        final a = await montarCobrarDesdeLaCasa(tester, repo: repo);
        expect(find.text('¿Qué le cobrás a Pedro?'), findsOneWidget);
        // La venta 0038 se paga entera desde otro lado (otro dispositivo sincronizado, otra pantalla).
        repo.base.cobros['otro'] = cobroDeEjemplo('otro', 120000, venta: 'v-38');

        await tester.tap(_cobrar);
        await asentarAgendar(tester);

        expect(pagina, findsOneWidget);
        expect(find.textContaining('saldo'), findsWidgets, reason: 'dice que no queda saldo');
        await tester.tap(cerrarCobro);
        await asentarAgendar(tester);
        expect(a.resultados, [false]);
        expect(a.rutas.aperturas - 1 - a.rutas.cierres, 0, reason: 'no queda ninguna ruta colgada');
        expect(repo.base.recibidos, isEmpty, reason: 'no se cobró nada');
      },
    );

    testWidgets('atrás del sistema desde el cobro: vuelve sin cobrar y no reabre «¿Qué venta?»', (
      tester,
    ) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]);
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo);
      await tester.tap(_cobrar);
      await asentarAgendar(tester);
      expect(pagina, findsOneWidget);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(a.resultados, [false]);
      expect(find.byType(HojaQueVenta), findsNothing);
      expect(pagina, findsNothing);
      expect(a.lanzados, isEmpty);
    });

    testWidgets('dos veces seguidas el flujo: el segundo ve el saldo nuevo y los ids no se pisan', (
      tester,
    ) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]);
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo);

      await tester.tap(_cobrar);
      await asentarAgendar(tester);
      await tester.enterText(find.descendant(of: pagina, matching: find.byType(TextField)), '100');
      await tester.pump();
      await tester.tap(find.byKey(const Key('venta_cta')));
      await asentarAgendar(tester);

      expect(repo.base.recibidos, hasLength(1));
      expect(repo.base.recibidos.single.ventaId, 'v-38');
      expect(repo.base.recibidos.single.montoCentavos, 10000);
      expect(a.idsGenerados, hasLength(1));
    });
  });

  group('Privacidad', () {
    test('las ventas y el paso no muestran talonario, monto ni qué se vendió en toString', () {
      final anterior = EquatableConfig.stringify;
      EquatableConfig.stringify = false;
      addTearDown(() => EquatableConfig.stringify = anterior);

      final venta = ventaDelCanvas38();
      final textos = [
        venta.toString(),
        PasoQueVenta.de([venta]).toString(),
        PasoQueVenta.de([venta, ventaDelCanvas45()]).toString(),
        const SinVentasConSaldo().toString(),
      ].join(' ');

      expect(textos, isNot(contains('0038')));
      expect(textos, isNot(contains('120000')));
      expect(textos, isNot(contains('Colección')));
    });
  });
}

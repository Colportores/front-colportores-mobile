// «$ Cobrar» de la vista 39 de punta a punta (HU-COB-001, #440): `FlujoCobrarDesdeLaCasa` con la hoja
// «¿Qué venta?» (C·08) y el cobro en efectivo (vista 28) reales, sobre un repositorio de cobros en
// memoria. Casos límite del flujo: una sola venta se salta, cancelar en cualquiera de los dos pasos,
// falla a mitad del cobro, dos cobros seguidos (el segundo ve el saldo nuevo), volver atrás y reentrar.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/hoja_que_venta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cobrar_desde_la_casa_arnes.dart';
import '../../helpers/cobro_arnes.dart';
import '../../helpers/persona_falsos.dart';

Finder get _cobrarEnLaHoja => find.byKey(ClavesQueVenta.cobrar);

Future<void> _cobrarMonto(WidgetTester tester, String monto) async {
  await escribirMonto(tester, monto);
  await tocarCobro(tester, botonRegistrar);
}

String _texto(String clave) => (find.byKey(Key(clave)).evaluate().single.widget as Text).data!;

void main() {
  group('Una sola venta con saldo: de «\$ Cobrar» al cobro', () {
    testWidgets('dado una venta, cuando se toca «\$ Cobrar», entonces salta C·08 y abre el cobro', (
      tester,
    ) async {
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38()]),
      );

      expect(find.byKey(ClavesQueVenta.lista), findsNothing);
      expect(pagina, findsOneWidget);
      expect(find.text('Venta 0038 · 12/10'), findsOneWidget);
      expect(_texto('cobro_saldo'), r'$ 1.200');
      expect(a.resultados, isEmpty);
    });

    testWidgets('cobrar parte y tocar «Listo» devuelve true y no escribe nada más que el cobro', (
      tester,
    ) async {
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38()]),
      );

      await _cobrarMonto(tester, '600');
      await tocarCobro(tester, find.text('Listo'));

      expect(a.resultados, [true]);
      expect(a.lanzados, isEmpty);
      expect(a.repo.base.recibidos.map((c) => c.montoCentavos), [60000]);
      expect(a.repo.base.recibidos.single.ventaId, 'v-38');
      expect(pagina, findsNothing);
    });

    testWidgets('el cobro se abre con el cliente de la casa ya resuelto', (tester) async {
      await montarCobrarDesdeLaCasa(tester, repo: cobranzasConVentas([ventaDelCanvas38()]));

      // El vínculo de Pedro con la casa viaja al cobro: la pantalla no lo vuelve a pedir.
      expect(find.textContaining('Pedro Gómez'), findsOneWidget);
    });
  });

  group('Varias ventas: C·08 y después el cobro', () {
    testWidgets('elegir la segunda y «Cobrar» abre el cobro de esa venta', (tester) async {
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );
      expect(find.text('¿Qué le cobrás a Pedro?'), findsOneWidget);

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.fila('v-45')));
      await tocarQueVenta(tester, _cobrarEnLaHoja);

      expect(find.byKey(ClavesQueVenta.lista), findsNothing);
      expect(pagina, findsOneWidget);
      expect(find.text('Venta 0045 · 20/10'), findsOneWidget);
      expect(_texto('cobro_saldo'), r'$ 240');

      await _cobrarMonto(tester, '240');
      expect(find.text('Venta pagada'), findsOneWidget);
      await tocarCobro(tester, find.text('Volver al mapa'));

      expect(a.resultados, [true]);
      expect(a.repo.base.recibidos.single.ventaId, 'v-45');
    });

    testWidgets('«Cancelar» en C·08: no se abre el cobro, no se escribe nada y devuelve false', (
      tester,
    ) async {
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cancelar));

      expect(a.resultados, [false]);
      expect(pagina, findsNothing);
      expect(a.repo.base.recibidos, isEmpty);
      expect(a.rutas.aperturas - 1, a.rutas.cierres);
    });

    testWidgets('cerrar el cobro sin cobrar devuelve false y no queda ningún cobro', (
      tester,
    ) async {
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );
      await tocarQueVenta(tester, _cobrarEnLaHoja);
      expect(pagina, findsOneWidget);

      await tocarCobro(tester, cerrarCobro);

      expect(a.resultados, [false]);
      expect(pagina, findsNothing);
      expect(a.repo.base.recibidos, isEmpty);
    });

    testWidgets(
      'volver atrás y reentrar: C·08 vuelve a ofrecerse entera con la más vieja elegida',
      (tester) async {
        final a = await montarCobrarDesdeLaCasa(
          tester,
          repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
        );
        await tocarQueVenta(tester, find.byKey(ClavesQueVenta.fila('v-45')));
        await tocarQueVenta(tester, _cobrarEnLaHoja);
        await tocarCobro(tester, cerrarCobro);
        expect(a.resultados, [false]);

        await abrirCobrarDesdeLaCasa(tester);
        expect(find.text('¿Qué le cobrás a Pedro?'), findsOneWidget);
        await tocarQueVenta(tester, _cobrarEnLaHoja);

        expect(find.text('Venta 0038 · 12/10'), findsOneWidget);
        expect(a.repo.lecturas, greaterThanOrEqualTo(2));
      },
    );
  });

  group('Falla a mitad de la acción', () {
    testWidgets(
      'el cobro falla al guardar: el botón vuelve a habilitarse y el reintento no duplica',
      (tester) async {
        final a = await montarCobrarDesdeLaCasa(
          tester,
          repo: cobranzasConVentas([ventaDelCanvas38()]),
        );
        a.repo.base.fallas.add(const FailureCobroNoGuardado(causa: 'x'));

        await _cobrarMonto(tester, '600');

        expect(find.byKey(const Key('cobro_error')), findsOneWidget);
        expect(a.resultados, isEmpty);
        expect(elBoton(tester).onPressed, isNotNull);

        await tocarCobro(tester, botonRegistrar);
        await tocarCobro(tester, find.text('Listo'));

        expect(a.resultados, [true]);
        expect(a.repo.base.cobros.values.where((c) => c.id.startsWith('cobro-')), hasLength(1));
        expect(a.idsGenerados, hasLength(1), reason: 'el reintento repite el id del cobro');
      },
    );

    testWidgets(
      'no se pudo leer las ventas: el aviso con «Reintentar» y, al leer, sigue el flujo',
      (tester) async {
        final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
          ..fallas.add(const FailureInesperado(causa: 'x'));
        final a = await montarCobrarDesdeLaCasa(tester, repo: repo);
        expect(find.byKey(ClavesQueVenta.error), findsOneWidget);
        expect(a.resultados, isEmpty);

        await tocarQueVenta(tester, find.byKey(ClavesQueVenta.reintentar));
        await tocarQueVenta(tester, _cobrarEnLaHoja);

        expect(pagina, findsOneWidget);
        expect(find.text('Venta 0038 · 12/10'), findsOneWidget);
      },
    );

    testWidgets('error de lectura y «Cancelar»: devuelve false y no deja nada trabado', (
      tester,
    ) async {
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..fallas.add(const FailureInesperado(causa: 'x'));
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo);

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cancelar));

      expect(a.resultados, [false]);
      expect(a.rutas.aperturas - 1, a.rutas.cierres);
    });
  });

  group('Dos cobros seguidos', () {
    testWidgets('el segundo ve el saldo que dejó el primero', (tester) async {
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
      );
      await tocarQueVenta(tester, _cobrarEnLaHoja);
      await _cobrarMonto(tester, '800');
      await tocarCobro(tester, find.text('Listo'));
      expect(a.resultados, [true]);

      await abrirCobrarDesdeLaCasa(tester);

      expect(find.text(r'$ 400'), findsOneWidget, reason: 'la 0038 quedó debiendo \$ 400');
      expect(find.text(r'$ 1.200'), findsNothing);
      expect(find.text(r'$ 240'), findsOneWidget);
    });

    testWidgets('el segundo cobro salda la última venta con saldo: no queda nada que ofrecer', (
      tester,
    ) async {
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38()]),
      );
      await _cobrarMonto(tester, '1200');
      expect(find.text('Venta pagada'), findsOneWidget);
      await tocarCobro(tester, find.text('Volver al mapa'));
      expect(a.resultados, [true]);

      await abrirCobrarDesdeLaCasa(tester);

      expect(find.byKey(ClavesQueVenta.sinSaldo), findsOneWidget);
      expect(pagina, findsNothing);
      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cerrar));
      expect(a.resultados, [true, false]);
    });
  });

  group('Sin ventas con saldo', () {
    testWidgets('lo dice y no abre el cobro', (tester) async {
      final repo = cobranzasConVentas([])..fija = const [];
      final a = await montarCobrarDesdeLaCasa(tester, repo: repo);

      expect(
        find.text('Pedro no tiene ventas con saldo. No queda nada para cobrar.'),
        findsOneWidget,
      );
      expect(pagina, findsNothing);

      await tocarQueVenta(tester, find.byKey(ClavesQueVenta.cerrar));

      expect(a.resultados, [false]);
    });
  });

  group('La persona o la casa no están', () {
    testWidgets('si la persona ya no vive en la casa, igual cobra y la pregunta va sin nombre', (
      tester,
    ) async {
      await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
        personas: [clienteDePersonas('otra', 'Ana', apellido: 'Gómez')],
      );

      expect(find.text('¿Qué venta cobrás?'), findsOneWidget);
      await tocarQueVenta(tester, _cobrarEnLaHoja);
      expect(pagina, findsOneWidget);
    });

    testWidgets('en un edificio sin depto elegido no hay dónde cobrar: lanza y no abre nada', (
      tester,
    ) async {
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38()]),
        espacioId: null,
      );

      expect(a.lanzados.single, isA<StateError>());
      expect(a.repo.lecturas, 0);
      expect(pagina, findsNothing);
    });

    testWidgets('sin sesión no se cobra: lanza y no abre nada', (tester) async {
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38()]),
        colportorId: '  ',
      );

      expect(a.lanzados.single, isA<StateError>());
      expect(pagina, findsNothing);
    });
  });

  group('Datos límite', () {
    testWidgets('textScaler 2.0 en 320×568: C·08 y el cobro se recorren hasta el final', (
      tester,
    ) async {
      final a = await montarCobrarDesdeLaCasa(
        tester,
        repo: cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]),
        escala: 2,
        tamano: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);

      await tocarQueVenta(tester, _cobrarEnLaHoja);
      expect(tester.takeException(), isNull);
      await _cobrarMonto(tester, '1200');
      await tocarCobro(tester, find.text('Volver al mapa'));

      expect(a.resultados, [true]);
    });
  });
}

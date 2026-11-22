// «Cobrar» con un plan de cuotas (vista 30 A, HU-COB-004, #166): 30A-05, el aviso de a qué cuota se
// aplica el pago que se está escribiendo, y el acceso a las cuotas desde el cobro.
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cobro_arnes.dart';
import '../../helpers/plan_de_cuotas_arnes.dart';

void main() {
  PlanDeCuotasEnMemoria planCon() => PlanDeCuotasEnMemoria(
    montoCentavos: 450000,
    cobradoCentavos: 330000,
    cuotas: [
      cuotaDe(1, dia: 26, mes: 10, monto: 83300, cubierta: true),
      cuotaDe(2, dia: 2, monto: 83300, pagado: 40000),
      cuotaDe(3, dia: 9, monto: 83400),
    ],
  );

  Future<PlanDeCuotasEnMemoria> montar(
    WidgetTester tester, {
    PlanDeCuotasEnMemoria? plan,
    double escala = 1,
    Size tamano = const Size(390, 844),
    CobranzasEnMemoria? cobros,
  }) async {
    final repo = plan ?? planCon();
    addTearDown(repo.cerrar);
    await montarCobro(
      tester,
      repo: cobros,
      escala: escala,
      tamano: tamano,
      overrides: [planDeCuotasRepositoryProvider.overrideWithValue(repo)],
    );
    return repo;
  }

  final aviso = find.byKey(const Key('cobro_aviso_cuota'));

  group('30A-05 · un pago se aplica a la cuota más próxima', () {
    testWidgets(
      'dado un pago de \$ 1.000 y la cuota 2 faltando \$ 433, cuando se escribe, dice que completa la 2 y adelanta \$ 567 de la 3',
      (tester) async {
        await montar(tester);

        await escribirMonto(tester, '1000');

        expect(
          find.text('Completa la cuota 2 (\$ 433) y adelanta \$ 567 de la cuota 3.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'dado un pago menor a lo que falta de la cuota, cuando se escribe, dice cuánto suma y cuánto falta',
      (tester) async {
        await montar(tester);

        await escribirMonto(tester, '200');

        expect(find.text('Suma \$ 200 a la cuota 2; faltan \$ 233.'), findsOneWidget);
      },
    );

    testWidgets('dado un pago justo a la cuota, cuando se escribe, dice que la completa', (
      tester,
    ) async {
      await montar(tester);

      await escribirMonto(tester, '433');

      expect(find.text('Completa la cuota 2 (\$ 433).'), findsOneWidget);
    });

    testWidgets('dado un pago que cubre dos cuotas, cuando se escribe, las nombra a las dos', (
      tester,
    ) async {
      final repo = PlanDeCuotasEnMemoria(
        montoCentavos: 450000,
        cobradoCentavos: 330000,
        cuotas: [
          cuotaDe(1, dia: 2, monto: 50000),
          cuotaDe(2, dia: 9, monto: 50000),
          cuotaDe(3, dia: 16, monto: 20000),
        ],
      );
      await montar(tester, plan: repo);

      await escribirMonto(tester, '1000');

      expect(find.text('Completa las cuotas 1 y 2 (\$ 1.000).'), findsOneWidget);
    });

    testWidgets(
      'dado un monto vacío, mayor al saldo o que no es un monto, cuando se escribe, no hay aviso de cuota',
      (tester) async {
        await montar(tester);

        expect(aviso, findsNothing);
        await escribirMonto(tester, '1500');
        expect(aviso, findsNothing);
        await escribirMonto(tester, 'abc');
        expect(aviso, findsNothing);
        await escribirMonto(tester, '');
        expect(aviso, findsNothing);
      },
    );

    testWidgets(
      'dado que el cobro se escribe y se corrige, cuando cambia el monto, el aviso sigue al monto',
      (tester) async {
        await montar(tester);

        await escribirMonto(tester, '1000');
        expect(find.textContaining('adelanta'), findsOneWidget);
        await escribirMonto(tester, '300');
        expect(find.textContaining('adelanta'), findsNothing);
        expect(find.text('Suma \$ 300 a la cuota 2; faltan \$ 133.'), findsOneWidget);
      },
    );

    testWidgets(
      'dado un plan sin cuotas por cobrar, cuando se escribe, no hay aviso: el pago es libre',
      (tester) async {
        await montar(
          tester,
          plan: PlanDeCuotasEnMemoria(
            montoCentavos: 450000,
            cobradoCentavos: 330000,
            cuotas: [cuotaDe(1, dia: 26, mes: 10, monto: 83300, cubierta: true)],
          ),
        );

        await escribirMonto(tester, '500');

        expect(aviso, findsNothing);
      },
    );

    testWidgets(
      'dada letra al 200 % en un teléfono chico, cuando se escribe el pago, el aviso se lee y no desborda',
      (tester) async {
        await montar(tester, escala: 2, tamano: const Size(320, 568));

        await escribirMonto(tester, '1000');

        expect(tester.takeException(), isNull);
        await traerAlAlcance(tester, aviso);
        expect(aviso, findsOneWidget);
      },
    );
  });

  group('el acceso a las cuotas desde el cobro', () {
    testWidgets(
      'dada una venta con saldo y sin plan, cuando se abre el cobro, ofrece «Pagar en cuotas» y abre el plan',
      (tester) async {
        await montar(
          tester,
          plan: PlanDeCuotasEnMemoria(montoCentavos: 450000, cobradoCentavos: 330000),
        );

        expect(find.text('Pagar en cuotas'), findsOneWidget);
        await tocarCobro(tester, find.byKey(const Key('cobro_cuotas')));

        expect(find.byKey(const Key('cuotas_plan_pagina')), findsOneWidget);
      },
    );

    testWidgets(
      'dada una venta con cuotas por cobrar, cuando se abre el cobro, ofrece «Ver las cuotas» y abre la lista',
      (tester) async {
        await montar(tester);

        expect(find.text('Ver las cuotas'), findsOneWidget);
        expect(find.text('Pagar en cuotas'), findsNothing);
        await tocarCobro(tester, find.byKey(const Key('cobro_cuotas')));

        expect(find.byKey(const Key('cuotas_lista_pagina')), findsOneWidget);
      },
    );

    testWidgets('dada una venta sin saldo, cuando se abre el cobro, no ofrece cuotas', (
      tester,
    ) async {
      await montar(
        tester,
        plan: PlanDeCuotasEnMemoria(montoCentavos: 450000, cobradoCentavos: 450000),
        cobros: CobranzasEnMemoria(cobradoAntes: 450000),
      );

      expect(find.byKey(const Key('cobro_venta_pagada')), findsOneWidget);
      expect(find.byKey(const Key('cobro_cuotas')), findsNothing);
    });

    testWidgets(
      'dado que no se puede leer el plan, cuando se abre el cobro, la pantalla sigue como siempre',
      (tester) async {
        await montar(tester, plan: PlanDeCuotasEnMemoria()..fallaAlLeer = true);

        expect(find.byKey(const Key('cobro_cuotas')), findsNothing);
        await escribirMonto(tester, '500');
        expect(aviso, findsNothing);
        expect(elBoton(tester).onPressed, isNotNull);
      },
    );

    testWidgets(
      'dado que se vuelve de las cuotas, cuando se cierra la lista, el cobro conserva lo escrito',
      (tester) async {
        await montar(tester);
        await escribirMonto(tester, '200');

        await tocarCobro(tester, find.byKey(const Key('cobro_cuotas')));
        await tocarCobro(tester, find.byKey(const Key('venta_atras')).last);

        expect(pagina, findsOneWidget);
        expect(tester.widget<TextField>(campoMonto).controller!.text, '200');
      },
    );
  });
}

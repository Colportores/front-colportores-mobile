// La última cuota del plan es lo que falta (decisión de Cristian del 03/11, #608): no se escribe a mano,
// se calcula sola cuando se cambian las anteriores. Las dos pantallas que editan montos («Pagar en
// cuotas» y «Modificar cuotas») la muestran de solo lectura, con un texto que dice qué pasa y cómo
// cambiarla; accesibilidad (semántica de campo no editable) y letra grande.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuotas_arnes.dart';
import '../../helpers/plan_de_cuotas_arnes.dart';

const _explicacion =
    'Es lo que falta: se calcula sola. Para cambiarla, cambiá las cuotas anteriores.';
const _explicacionAjustada = 'Se ajustó. $_explicacion';
const _unica =
    'Es la única cuota que queda y es lo que falta: no se cambia. Para otro día, reprogramala '
    'desde la Agenda.';

void main() {
  bool botonApagado(WidgetTester tester) => elBotonPrincipal(tester).onPressed == null;

  /// La venta de \$ 2.500 con la cuota 1 pagada: quedan la 2 y la 3 (la última).
  PlanDeCuotasEnMemoria planConUnaPagada() => PlanDeCuotasEnMemoria(
    montoCentavos: 250000,
    cobradoCentavos: 83300,
    cuotas: [
      cuotaDe(1, dia: 26, mes: 10, monto: 83300, cubierta: true),
      cuotaDe(2, dia: 2, monto: 83300),
      cuotaDe(3, dia: 9, monto: 83400),
    ],
  );

  /// La cuota 1 y la 2 pagadas: la única abierta es la 3, que es la última.
  PlanDeCuotasEnMemoria planConUnaSolaAbierta() => PlanDeCuotasEnMemoria(
    montoCentavos: 250000,
    cobradoCentavos: 166600,
    cuotas: [
      cuotaDe(1, dia: 26, mes: 10, monto: 83300, cubierta: true),
      cuotaDe(2, dia: 2, monto: 83300, cubierta: true),
      cuotaDe(3, dia: 9, monto: 83400),
    ],
  );

  group('«Pagar en cuotas»', () {
    testWidgets(
      'dado un plan de 3 cuotas, cuando se abre, la última no es un campo editable y explica por qué',
      (tester) async {
        await montarCuotas(tester);

        expect(campoDeCuota(0), findsOneWidget);
        expect(campoDeCuota(1), findsOneWidget);
        expect(campoDeCuota(2), findsNothing, reason: 'la última se calcula, no se escribe');
        expect(textoDeCuota(tester, 2), '\$ 834');
        expect(find.text(_explicacion), findsOneWidget);
      },
    );

    testWidgets(
      'dada una cuota anterior cambiada, cuando se escribe, la última se recalcula como lo que falta y lo dice',
      (tester) async {
        final arnes = await montarCuotas(tester);

        await escribirCuota(tester, 0, '900');
        expect([textoDeCuota(tester, 1), textoDeCuota(tester, 2)], ['\$ 800', '\$ 800']);
        expect(find.text(_explicacionAjustada), findsOneWidget);

        await escribirCuota(tester, 1, '1000');
        expect(textoDeCuota(tester, 2), '\$ 600');

        await tocarEnCuotas(tester, botonPrincipal);
        expect(arnes.plan.ultimoPlan!.cuotas.map((c) => c.montoCentavos), [90000, 100000, 60000]);
        expect(
          arnes.plan.ultimoPlan!.cuotas.fold<int>(0, (a, c) => a + c.montoCentavos),
          250000,
          reason: 'la última es lo que falta del saldo',
        );
      },
    );

    testWidgets(
      'dado un lector de pantalla, cuando recorre la última cuota, la lee como campo de solo lectura y calculada',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await montarCuotas(tester);

        final ultima = find.bySemanticsLabel(
          RegExp(r'Monto de la cuota .*\$ 834\. Calculada, no se edita\.'),
        );
        expect(ultima, findsOneWidget);
        expect(tester.getSemantics(ultima), isSemantics(isReadOnly: true));
        expect(
          find.bySemanticsLabel(RegExp(r'Monto de la cuota 1 · .*Calculada')),
          findsNothing,
          reason: 'las anteriores siguen siendo campos para escribir',
        );
        semantica.dispose();
      },
    );

    testWidgets(
      'dado el texto al 200 %, cuando se arma el plan, la última cuota y su explicación entran sin cortarse',
      (tester) async {
        await montarCuotas(tester, escala: 2, tamano: const Size(320, 568));

        await traerCuotaAlAlcance(tester, find.byKey(const Key('cuotas_fila_2')));
        expect(tester.takeException(), isNull);
        expect(find.text(_explicacion), findsOneWidget);
        expect(textoDeCuota(tester, 2), '\$ 834');
        expect(botonApagado(tester), isFalse);
      },
    );

    testWidgets(
      'dado un plan de 2 cuotas, cuando se cambia la primera, la segunda es lo que falta, incluso con montos largos',
      (tester) async {
        await montarCuotas(tester);
        await tocarEnCuotas(tester, find.byKey(const Key('cuotas_menos')));
        expect(campoDeCuota(1), findsNothing);

        await escribirCuota(tester, 0, '1.000,50');

        expect(textoDeCuota(tester, 1), '\$ 1.499,50');
        expect(botonApagado(tester), isFalse);
      },
    );

    testWidgets(
      'dada una falla del rechazo "la última se escribió a mano", cuando se crea, el aviso guía y el botón vuelve a "Reintentar"',
      (tester) async {
        final arnes = await montarCuotas(tester);
        arnes.plan.fallaAlCrear = const FailurePlanDeCuotas(MotivoPlanDeCuotas.ultimaCuota);

        await tocarEnCuotas(tester, botonPrincipal);

        expect(find.byKey(const Key('cuotas_error')), findsOneWidget);
        expect(
          find.text(
            'La última cuota es lo que falta y no se escribe a mano. Cambiá las cuotas anteriores '
            'y se calcula sola.',
          ),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsOneWidget);
        expect(botonApagado(tester), isFalse);
      },
    );
  });

  group('«Modificar cuotas»', () {
    testWidgets(
      'dado un plan con una cuota pagada, cuando se abre, la última abierta es de solo lectura y las otras se escriben',
      (tester) async {
        await montarCuotas(tester, pantalla: PantallaDeCuotas.modificar, plan: planConUnaPagada());

        expect(campoDeCuota(1), findsNothing, reason: 'la pagada no se toca');
        expect(campoDeCuota(2), findsOneWidget);
        expect(campoDeCuota(3), findsNothing, reason: 'la última se calcula');
        expect(textoDeCuota(tester, 3), '\$ 834');
        expect(find.text(_explicacion), findsOneWidget);
      },
    );

    testWidgets(
      'dada una cuota anterior cambiada, cuando se guarda, se manda la última como lo que falta',
      (tester) async {
        final arnes = await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: planConUnaPagada(),
        );

        await escribirCuota(tester, 2, '1000');

        expect(textoDeCuota(tester, 3), '\$ 667');
        expect(find.text(_explicacionAjustada), findsOneWidget);
        await tocarEnCuotas(tester, botonPrincipal);

        expect(
          {for (final c in arnes.plan.ultimoCambio!.cambios) c.agendaId: c.montoCentavos},
          {'q-2': 100000, 'q-3': 66700},
        );
        expect(arnes.resultados, [true]);
      },
    );

    testWidgets(
      'dada una sola cuota abierta (es la última), cuando se abre, no hay nada para escribir y lo dice',
      (tester) async {
        await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: planConUnaSolaAbierta(),
        );

        expect(campoDeCuota(3), findsNothing);
        expect(textoDeCuota(tester, 3), '\$ 834');
        expect(find.text(_unica), findsOneWidget);
        expect(find.text(_explicacion), findsNothing);
        expect(botonApagado(tester), isTrue, reason: 'sin cambios no hay nada que guardar');
      },
    );

    testWidgets(
      'dado el texto al 200 %, cuando se abre, la última cuota y su explicación entran sin cortarse',
      (tester) async {
        await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: planConUnaPagada(),
          escala: 2,
          tamano: const Size(320, 568),
        );

        await traerCuotaAlAlcance(tester, find.byKey(const Key('cuotas_fila_3')));
        expect(tester.takeException(), isNull);
        expect(find.text(_explicacion), findsOneWidget);
      },
    );

    testWidgets(
      'dada una falla de la última escrita a mano al guardar, cuando se guarda, el aviso guía y se puede reintentar',
      (tester) async {
        final arnes = await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: planConUnaPagada(),
        );
        arnes.plan.fallaAlModificar = const FailurePlanDeCuotas(MotivoPlanDeCuotas.ultimaCuota);
        await escribirCuota(tester, 2, '1000');

        await tocarEnCuotas(tester, botonPrincipal);

        expect(find.byKey(const Key('cuotas_error')), findsOneWidget);
        expect(find.textContaining('Cambiá las cuotas anteriores'), findsWidgets);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(botonApagado(tester), isFalse);
        expect(textoDeCuota(tester, 2), '1000', reason: 'lo escrito se conserva');
      },
    );
  });
}

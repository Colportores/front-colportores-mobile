// «Cuotas» de una venta (vista 30 A, HU-COB-004, #166): 30A-04 (creado), 30A-06 (vencida) y 30A-07
// (sin saldo), más «Modificar cuotas» (30A-09, id 30A-11 del canvas) y sus casos límite.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agendar_visita_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/cuotas_arnes.dart';
import '../../helpers/plan_de_cuotas_arnes.dart';

/// El plan del canvas 30A-04: venta de \$ 2.500 con la cuota 1 pagada, la 2 con \$ 400 de \$ 833 y la 3
/// agendada.
PlanDeCuotasEnMemoria planConUnaPagadaYUnaParcial() => PlanDeCuotasEnMemoria(
  montoCentavos: 250000,
  cobradoCentavos: 83300 + 40000,
  cuotas: [
    cuotaDe(
      1,
      dia: 26,
      mes: 10,
      monto: 83300,
      cubierta: true,
      cubiertaEl: DateTime(2026, 10, 26, 12),
    ),
    cuotaDe(2, dia: 2, monto: 83300, pagado: 40000),
    cuotaDe(3, dia: 9, monto: 83400),
  ],
);

void main() {
  bool botonApagado(WidgetTester tester) => elBotonPrincipal(tester).onPressed == null;

  group('30A-04 · el plan creado', () {
    testWidgets(
      'dado un plan con una cuota pagada, una parcial y una agendada, cuando se abre, las muestra con su estado',
      (tester) async {
        await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.lista,
          plan: planConUnaPagadaYUnaParcial(),
        );

        expect(find.text('VENTA 0042'), findsOneWidget);
        expect(find.text('Cuotas'), findsOneWidget);
        expect(find.text('María Fernández'), findsOneWidget);
        expect(find.text('Venta 0042 · 12/10'), findsOneWidget);
        expect(find.text('PLAN · 3 CUOTAS SEMANALES'), findsOneWidget);

        expect(find.text('CUOTA 1 · 26/10'), findsOneWidget);
        expect(find.text('\$ 833'), findsOneWidget);
        expect(find.text('Pagada el 26/10'), findsOneWidget);

        expect(find.text('CUOTA 2 · 02/11'), findsOneWidget);
        expect(find.text('\$ 400 de \$ 833'), findsOneWidget);
        expect(find.text('Parcial · faltan \$ 433'), findsOneWidget);
        expect(find.text('Parcial'), findsOneWidget);

        expect(find.text('CUOTA 3 · 09/11'), findsOneWidget);
        expect(find.text('\$ 834'), findsOneWidget);
        expect(find.text('Agendada · 09/11 10:00'), findsOneWidget);

        expect(find.text('Modificar cuotas'), findsOneWidget);
        expect(find.byKey(const Key('cuotas_aviso_vencida')), findsNothing);
      },
    );

    testWidgets('dado un plan mensual, cuando se abre, el rótulo lo dice', (tester) async {
      await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.lista,
        plan: PlanDeCuotasEnMemoria(
          cuotas: [cuotaDe(1, dia: 26, mes: 10, monto: 125000), cuotaDe(2, dia: 26, monto: 125000)],
        ),
      );

      expect(find.text('PLAN · 2 CUOTAS MENSUALES'), findsOneWidget);
    });

    testWidgets(
      'dado un cobro que llega con la pantalla abierta, cuando cambia el plan, la lista se actualiza sola',
      (tester) async {
        final arnes = await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.lista,
          plan: planConUnaPagadaYUnaParcial(),
        );
        expect(find.text('\$ 400 de \$ 833'), findsOneWidget);

        arnes.plan.poner(
          cobradoCentavos: 250000 - 83400,
          cuotas: [
            cuotaDe(1, dia: 26, mes: 10, monto: 83300, cubierta: true),
            cuotaDe(2, dia: 2, monto: 83300, cubierta: true),
            cuotaDe(3, dia: 9, monto: 83400),
          ],
        );
        await asentarAgendar(tester);

        expect(find.text('\$ 400 de \$ 833'), findsNothing);
        expect(find.text('Parcial'), findsNothing);
        expect(find.text('Pagada el 26/10'), findsNWidgets(2));
      },
    );

    testWidgets(
      'dado un plan con todas las cuotas pagadas y saldo todavía, cuando se abre, ofrece armar otro',
      (tester) async {
        await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.lista,
          plan: PlanDeCuotasEnMemoria(
            cobradoCentavos: 125000,
            cuotas: [cuotaDe(1, dia: 26, mes: 10, monto: 125000, cubierta: true)],
          ),
        );

        expect(find.text('Pagar en cuotas'), findsOneWidget);
        expect(find.text('Modificar cuotas'), findsNothing);
      },
    );

    testWidgets(
      'dado un plan largo con letra al 200 %, cuando se abre, no desborda y se llega a cada cuota',
      (tester) async {
        await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.lista,
          escala: 2,
          tamano: const Size(320, 568),
          plan: PlanDeCuotasEnMemoria(
            montoCentavos: 600000,
            cuotas: [
              for (var i = 1; i <= 12; i++)
                cuotaDe(i, dia: i, mes: 12, monto: 50000, pagado: i == 1 ? 12500 : 0),
            ],
          ),
        );

        expect(tester.takeException(), isNull);
        await traerCuotaAlAlcance(tester, find.byKey(const Key('cuota_12')));
        expect(find.byKey(const Key('cuota_12')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('30A-06 · cuota vencida', () {
    testWidgets(
      'dada una cuota cuyo día ya pasó, cuando se abre, la marca y avisa con «Agendar cobranza»',
      (tester) async {
        final arnes = await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.lista,
          plan: planConUnaPagadaYUnaParcial(),
          abrir: false,
        );
        arnes.ahora = DateTime(2026, 11, 3, 9);
        await abrirCuotas(tester);

        expect(
          find.text('La cuota 2 venció el 02/11. Te avisamos con una notificación.'),
          findsOneWidget,
        );
        expect(find.text('Agendar cobranza'), findsOneWidget);
        expect(find.text('Vencida'), findsOneWidget);
      },
    );

    testWidgets('dado «Agendar cobranza», cuando se toca, abre «Agendar una visita» de cobranza', (
      tester,
    ) async {
      final arnes = await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.lista,
        plan: planConUnaPagadaYUnaParcial(),
        abrir: false,
      );
      arnes.ahora = DateTime(2026, 11, 3, 9);
      await abrirCuotas(tester);

      await tocarEnCuotas(tester, find.text('Agendar cobranza'));

      expect(find.byType(AgendarVisitaPage), findsOneWidget);
    });

    testWidgets('dada la cuota de hoy, cuando se abre, todavía no venció', (tester) async {
      final arnes = await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.lista,
        plan: planConUnaPagadaYUnaParcial(),
        abrir: false,
      );
      arnes.ahora = DateTime(2026, 11, 2, 18);
      await abrirCuotas(tester);

      expect(find.byKey(const Key('cuotas_aviso_vencida')), findsNothing);
      expect(find.text('Vencida'), findsNothing);
    });
  });

  group('30A-07 · sin saldo', () {
    testWidgets(
      'dada una venta pagada sin plan, cuando se abre, dice que no hay nada que repartir y no ofrece botón',
      (tester) async {
        await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.lista,
          plan: PlanDeCuotasEnMemoria(montoCentavos: 450000, cobradoCentavos: 450000),
        );

        expect(find.text('La venta está pagada'), findsOneWidget);
        expect(find.text('No hay saldo para repartir en cuotas.'), findsOneWidget);
        expect(botonPrincipal, findsNothing);
      },
    );
  });

  group('sin plan, con saldo', () {
    testWidgets(
      'dada una venta sin plan, cuando se abre, lo dice y «Pagar en cuotas» arma el plan sin duplicar la lista',
      (tester) async {
        final arnes = await montarCuotas(tester, pantalla: PantallaDeCuotas.lista);
        expect(find.text('Esta venta no tiene plan de cuotas'), findsOneWidget);

        await tocarEnCuotas(tester, find.text('Pagar en cuotas'));
        expect(paginaPlan, findsOneWidget);
        await tocarEnCuotas(tester, botonPrincipal);

        expect(paginaPlan, findsNothing);
        expect(paginaLista, findsOneWidget, reason: 'una sola lista, la de abajo');
        expect(find.text('Plan creado. Agendamos 3 cobranzas.'), findsOneWidget);
        expect(find.text('PLAN · 3 CUOTAS SEMANALES'), findsOneWidget);
        expect(arnes.plan.pedidosDeCrear, 1);

        await tocarEnCuotas(tester, volverDeCuotas);
        expect(arnes.resultados, [true]);
      },
    );

    testWidgets(
      'dado el plan descartado, cuando se vuelve a la lista, sigue sin plan y sin aviso',
      (tester) async {
        final arnes = await montarCuotas(tester, pantalla: PantallaDeCuotas.lista);
        await tocarEnCuotas(tester, find.text('Pagar en cuotas'));
        await tocarEnCuotas(tester, volverDeCuotas);

        expect(paginaLista, findsOneWidget);
        expect(find.text('Esta venta no tiene plan de cuotas'), findsOneWidget);
        expect(find.textContaining('Plan creado'), findsNothing);
        expect(arnes.resultados, isEmpty);
      },
    );
  });

  group('estados de la lectura', () {
    testWidgets(
      'dado que no se pueden leer las cuotas (32B-07), cuando se abre, avisa y «Reintentar» las vuelve a leer',
      (tester) async {
        final arnes = await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.lista,
          plan: PlanDeCuotasEnMemoria()..fallaAlLeer = true,
        );
        expect(find.text('No pudimos leer las cuotas guardadas en tu teléfono.'), findsOneWidget);
        expect(find.text('Esta venta no tiene plan de cuotas'), findsNothing);

        arnes.plan.fallaAlLeer = false;
        await tocarEnCuotas(tester, find.text('Reintentar'));
        expect(find.text('Esta venta no tiene plan de cuotas'), findsOneWidget);
      },
    );

    testWidgets('dada una venta que ya no está, cuando se abre, lo dice', (tester) async {
      await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.lista,
        plan: PlanDeCuotasEnMemoria()..ventaAusente = true,
      );
      expect(find.byKey(const Key('cuotas_sin_venta')), findsOneWidget);
    });

    testWidgets(
      'dado que se está leyendo (32B-06), cuando se abre, muestra el esqueleto antes del contenido',
      (tester) async {
        final lectura = Completer<void>();
        await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.lista,
          plan: PlanDeCuotasEnMemoria()..retenerLaLectura = lectura,
          abrir: false,
        );
        await tester.tap(find.text('abrir cuotas'));
        await asentarAgendar(tester);
        expect(find.byKey(const Key('cuotas_cargando')), findsOneWidget);

        lectura.complete();
        await asentarAgendar(tester);
        expect(find.byKey(const Key('cuotas_cargando')), findsNothing);
        expect(find.byKey(const Key('cuotas_sin_plan')), findsOneWidget);
      },
    );
  });

  group('30A-09 · modificar las cuotas', () {
    /// El canvas: venta de \$ 2.500, la cuota 1 pagada y saldo \$ 1.667.
    PlanDeCuotasEnMemoria planConUnaPagada() => PlanDeCuotasEnMemoria(
      montoCentavos: 250000,
      cobradoCentavos: 83300,
      cuotas: [
        cuotaDe(1, dia: 26, mes: 10, monto: 83300, cubierta: true),
        cuotaDe(2, dia: 2, monto: 83300),
        cuotaDe(3, dia: 9, monto: 83400),
      ],
    );

    testWidgets(
      'dado un plan con una cuota pagada, cuando se abre «Modificar cuotas», la pagada no se toca y las otras sí',
      (tester) async {
        await montarCuotas(tester, pantalla: PantallaDeCuotas.modificar, plan: planConUnaPagada());

        expect(find.text('Modificar cuotas'), findsOneWidget);
        expect(find.text('María Fernández · saldo \$ 1.667'), findsOneWidget);
        expect(find.text('CUOTAS'), findsOneWidget);
        expect(find.text('Ya está pagada: no cambia.'), findsOneWidget);
        expect(find.byKey(const Key('cuotas_fila_1')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('cuotas_fila_1')),
            matching: find.byType(TextField),
          ),
          findsNothing,
        );
        expect(textoDeCuotaNumero(tester, 2), '\$ 833');
        expect(textoDeCuotaNumero(tester, 3), '\$ 834');
        expect(
          find.text(
            'Solo se ajustan las cuotas que no están cerradas. Al guardar se reprograman sus cobranzas.',
          ),
          findsOneWidget,
        );
        expect(find.text('Guardar cuotas'), findsOneWidget);
        expect(botonApagado(tester), isTrue, reason: 'sin cambios no hay nada que guardar');
      },
    );

    testWidgets(
      'dada la cuota 2 cambiada a \$ 1.000, cuando se escribe, la 3 se ajusta a \$ 667; al guardar se reprograman las dos y se devuelve true',
      (tester) async {
        final arnes = await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: planConUnaPagada(),
        );

        await escribirCuota(tester, 2, '1000');

        expect(textoDeCuotaNumero(tester, 3), '\$ 667');
        expect(find.text('Se ajustó'), findsOneWidget);
        expect(botonApagado(tester), isFalse);

        await tocarEnCuotas(tester, botonPrincipal);

        expect(arnes.plan.pedidosDeModificar, 1);
        expect(
          {for (final c in arnes.plan.ultimoCambio!.cambios) c.agendaId: c.montoCentavos},
          {'q-2': 100000, 'q-3': 66700},
        );
        expect(paginaModificar, findsNothing);
        expect(arnes.resultados, [true]);
      },
    );

    testWidgets(
      'dada una cuota mayor a lo que falta repartir, cuando se escribe, se marca y no deja guardar',
      (tester) async {
        await montarCuotas(tester, pantalla: PantallaDeCuotas.modificar, plan: planConUnaPagada());

        await escribirCuota(tester, 2, '2000');

        expect(find.text('El saldo es \$ 1.667: la cuota no puede ser mayor.'), findsOneWidget);
        expect(botonApagado(tester), isTrue);
      },
    );

    testWidgets(
      'dada una cuota con \$ 400 ya cobrados, cuando se baja de ahí, avisa y no deja guardar',
      (tester) async {
        await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: planConUnaPagadaYUnaParcial(),
        );

        await escribirCuota(tester, 2, '300');

        expect(
          find.text('No puede ser menos de lo que ya se cobró de esta cuota.'),
          findsOneWidget,
        );
        expect(botonApagado(tester), isTrue);
      },
    );

    testWidgets(
      'dada una falla al guardar, cuando se guarda, avisa, conserva lo escrito y el botón vuelve; el reintento sale bien',
      (tester) async {
        final arnes = await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: planConUnaPagada(),
        );
        arnes.plan.fallaAlModificar = const FailureCuotasNoGuardadas(causa: 'x');
        await escribirCuota(tester, 2, '1000');

        await tocarEnCuotas(tester, botonPrincipal);

        expect(
          find.text('No pudimos guardar las cuotas. No cambió nada: probá de nuevo.'),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsOneWidget);
        expect(botonApagado(tester), isFalse);
        expect(textoDeCuotaNumero(tester, 2), '1000');

        await tocarEnCuotas(tester, botonPrincipal);
        expect(arnes.plan.pedidosDeModificar, 2);
        expect(arnes.resultados, [true]);
      },
    );

    testWidgets(
      'dado un doble toque en «Guardar cuotas», cuando se toca dos veces, se guarda una vez',
      (tester) async {
        final arnes = await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: planConUnaPagada(),
        );
        await escribirCuota(tester, 2, '1000');

        await tester.tap(botonPrincipal);
        await tester.tap(botonPrincipal, warnIfMissed: false);
        await asentarAgendar(tester);

        expect(arnes.plan.pedidosDeModificar, 1);
      },
    );

    testWidgets(
      'dado lo escrito, cuando se toca ✕, pregunta; «Descartar» sale sin guardar y al reentrar vuelven los montos del plan',
      (tester) async {
        final arnes = await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: planConUnaPagada(),
        );
        await escribirCuota(tester, 2, '1000');

        await tocarEnCuotas(tester, volverDeCuotas);
        expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
        await tester.tap(find.text('Descartar'));
        await asentarAgendar(tester);

        expect(arnes.resultados, [false]);
        expect(arnes.plan.pedidosDeModificar, 0);

        await abrirCuotas(tester);
        expect(textoDeCuotaNumero(tester, 2), '\$ 833');
        expect(textoDeCuotaNumero(tester, 3), '\$ 834');
      },
    );

    testWidgets('dado un cambio y vuelto al monto original, cuando se toca ✕, sale sin preguntar', (
      tester,
    ) async {
      final arnes = await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.modificar,
        plan: planConUnaPagada(),
      );
      await escribirCuota(tester, 2, '1000');
      await escribirCuota(tester, 2, '833');
      await escribirCuota(tester, 3, '834');

      await tocarEnCuotas(tester, volverDeCuotas);

      expect(find.text('¿Descartar lo que escribiste?'), findsNothing);
      expect(arnes.resultados, [false]);
    });

    testWidgets('dado un plan donde todo está pagado, cuando se abre, lo dice y deja volver', (
      tester,
    ) async {
      final arnes = await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.modificar,
        plan: PlanDeCuotasEnMemoria(
          cobradoCentavos: 250000,
          cuotas: [
            cuotaDe(1, dia: 26, mes: 10, monto: 125000, cubierta: true),
            cuotaDe(2, dia: 2, monto: 125000, cubierta: true),
          ],
        ),
      );

      expect(find.text('Todas las cuotas están pagadas.'), findsOneWidget);
      await tocarEnCuotas(tester, find.text('Volver'));
      expect(arnes.resultados, [false]);
    });

    testWidgets(
      'dado un cobro que llega mientras se abre y no se escribió nada, cuando cambia el plan, el formulario sigue al plan',
      (tester) async {
        final arnes = await montarCuotas(
          tester,
          pantalla: PantallaDeCuotas.modificar,
          plan: planConUnaPagada(),
        );
        arnes.plan.poner(
          cobradoCentavos: 83300 + 83300,
          cuotas: [
            cuotaDe(1, dia: 26, mes: 10, monto: 83300, cubierta: true),
            cuotaDe(2, dia: 2, monto: 83300, cubierta: true),
            cuotaDe(3, dia: 9, monto: 83400),
          ],
        );
        await asentarAgendar(tester);

        expect(find.text('Ya está pagada: no cambia.'), findsNWidgets(2));
        expect(find.text('María Fernández · saldo \$ 834'), findsOneWidget);
      },
    );

    testWidgets('dado un plan largo con letra al 200 %, cuando se abre, no desborda', (
      tester,
    ) async {
      await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.modificar,
        escala: 2,
        tamano: const Size(320, 568),
        plan: PlanDeCuotasEnMemoria(
          montoCentavos: 1200000,
          cuotas: [for (var i = 1; i <= 12; i++) cuotaDe(i, dia: i, mes: 12, monto: 100000)],
        ),
      );
      await escribirCuota(tester, 12, '500');
      expect(tester.takeException(), isNull);
      expect(botonApagado(tester), isFalse);
    });

    testWidgets('dada una venta que no se puede leer, cuando se abre, avisa y deja reintentar', (
      tester,
    ) async {
      await montarCuotas(
        tester,
        pantalla: PantallaDeCuotas.modificar,
        plan: PlanDeCuotasEnMemoria()..fallaAlLeer = true,
      );
      expect(find.byKey(const Key('cuotas_error_lectura')), findsOneWidget);
    });
  });
}

/// Lo que dice el campo de monto de la cuota número [n] (desde 1).
String textoDeCuotaNumero(WidgetTester tester, int n) =>
    tester.widget<TextField>(campoDeCuota(n)).controller!.text;

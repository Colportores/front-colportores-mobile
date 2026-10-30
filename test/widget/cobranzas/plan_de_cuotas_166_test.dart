// «Pagar en cuotas» (vista 30 A, HU-COB-004, #166): los artboards 30A-01, 30A-02, 30A-02B, 30A-02C,
// 30A-03 y 30A-08 y sus casos límite, con un plan en memoria que respeta las reglas del real.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/cuotas_arnes.dart';
import '../../helpers/plan_de_cuotas_arnes.dart';

void main() {
  bool botonApagado(WidgetTester tester) => elBotonPrincipal(tester).onPressed == null;

  group('30A-01 · armar el plan', () {
    testWidgets(
      'dada una venta con saldo de \$ 2.500, cuando se abre, propone 3 cuotas semanales de partes iguales con el redondeo en la última',
      (tester) async {
        await montarCuotas(tester);

        expect(find.text('Pagar en cuotas'), findsOneWidget);
        expect(find.text('María Fernández · saldo \$ 2.500'), findsOneWidget);
        expect(find.text('Cantidad de cuotas'), findsOneWidget);
        expect(find.text('De 2 a 12'), findsOneWidget);
        expect(find.byKey(const Key('cuotas_cantidad')), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('Semanal'), findsOneWidget);
        expect(find.text('Mensual'), findsOneWidget);
        expect(find.text('PRIMERA CUOTA'), findsOneWidget);
        expect(find.text('Lunes 26/10'), findsOneWidget);
        expect(find.text('CUOTAS · TOCÁ UN MONTO PARA CAMBIARLO'), findsOneWidget);
        expect(find.text('1 · lun 26/10'), findsOneWidget);
        expect(find.text('2 · lun 02/11'), findsOneWidget);
        expect(find.text('3 · lun 09/11'), findsOneWidget);
        expect(
          [for (var i = 0; i < 3; i++) textoDeCuota(tester, i)],
          ['\$ 833', '\$ 833', '\$ 834'],
        );
        expect(
          find.text('Agendamos una cobranza para cada cuota, con recordatorio.'),
          findsOneWidget,
        );
        expect(find.text('Crear plan'), findsOneWidget);
        expect(botonApagado(tester), isFalse);
      },
    );

    testWidgets(
      'dado un plan, cuando se cambia la cantidad, se reparte de nuevo y los extremos se apagan',
      (tester) async {
        await montarCuotas(tester);

        await tocarEnCuotas(tester, find.byKey(const Key('cuotas_mas')));
        expect(
          [for (var i = 0; i < 4; i++) textoDeCuota(tester, i)],
          ['\$ 625', '\$ 625', '\$ 625', '\$ 625'],
        );

        for (var i = 0; i < 8; i++) {
          await tocarEnCuotas(tester, find.byKey(const Key('cuotas_mas')));
        }
        expect(find.text('12'), findsOneWidget);
        expect(tester.widget<IconButton>(find.byKey(const Key('cuotas_mas'))).onPressed, isNull);

        for (var i = 0; i < 10; i++) {
          await tocarEnCuotas(tester, find.byKey(const Key('cuotas_menos')));
        }
        expect(find.text('2'), findsOneWidget);
        expect(tester.widget<IconButton>(find.byKey(const Key('cuotas_menos'))).onPressed, isNull);
      },
    );

    testWidgets(
      'dado un plan, cuando se crea, se agendan las 3 cobranzas, se abre la lista con el aviso y se devuelve true',
      (tester) async {
        final arnes = await montarCuotas(tester);

        await tocarEnCuotas(tester, botonPrincipal);

        expect(arnes.plan.pedidosDeCrear, 1);
        final pedido = arnes.plan.ultimoPlan!;
        expect(pedido.cuotas.map((c) => c.montoCentavos), [83300, 83300, 83400]);
        expect(pedido.cuotas.map((c) => c.fecha), [
          DateTime(2026, 10, 26, 10),
          DateTime(2026, 11, 2, 10),
          DateTime(2026, 11, 9, 10),
        ]);
        expect(paginaLista, findsOneWidget);
        expect(paginaPlan, findsNothing);
        expect(find.text('Plan creado. Agendamos 3 cobranzas.'), findsOneWidget);
        expect(arnes.telefono.recordatorios.programados, hasLength(3));

        await tester.tap(volverDeCuotas);
        await asentarAgendar(tester);
        expect(arnes.resultados, [true]);
      },
    );
  });

  group('30A-02 · mensual', () {
    testWidgets(
      'dado un plan mensual de 2 cuotas, cuando se arma, la segunda cae el mismo día del mes siguiente',
      (tester) async {
        final arnes = await montarCuotas(tester);

        await tocarEnCuotas(tester, find.text('Mensual'));
        await tocarEnCuotas(tester, find.byKey(const Key('cuotas_menos')));

        expect(find.text('1 · lun 26/10'), findsOneWidget);
        expect(find.text('2 · jue 26/11'), findsOneWidget);
        expect([for (var i = 0; i < 2; i++) textoDeCuota(tester, i)], ['\$ 1.250', '\$ 1.250']);

        await tocarEnCuotas(tester, botonPrincipal);
        expect(arnes.plan.ultimoPlan!.cuotas.last.fecha, DateTime(2026, 11, 26, 10));
      },
    );
  });

  group('30A-02B · cambiás una cuota: el resto se ajusta', () {
    testWidgets(
      'dada la primera cuota subida a \$ 900, cuando se escribe, las otras dos se reparten \$ 1.600 y dicen «Se ajustó»',
      (tester) async {
        final arnes = await montarCuotas(tester);

        await escribirCuota(tester, 0, '900');

        expect(textoDeCuota(tester, 0), '900');
        expect([textoDeCuota(tester, 1), textoDeCuota(tester, 2)], ['\$ 800', '\$ 800']);
        expect(find.text('Se ajustó'), findsNWidgets(2));
        expect(botonApagado(tester), isFalse);

        await tocarEnCuotas(tester, botonPrincipal);
        expect(arnes.plan.ultimoPlan!.cuotas.map((c) => c.montoCentavos), [90000, 80000, 80000]);
      },
    );

    testWidgets('dada la última cuota cambiada, cuando se escribe, nada más se ajusta', (
      tester,
    ) async {
      await montarCuotas(tester);

      await escribirCuota(tester, 2, '700');

      expect([textoDeCuota(tester, 0), textoDeCuota(tester, 1)], ['\$ 833', '\$ 833']);
      expect(find.text('Se ajustó'), findsNothing);
      expect(botonApagado(tester), isFalse);
    });

    testWidgets('dado un monto con coma y con punto de miles, cuando se escribe, se entiende', (
      tester,
    ) async {
      await montarCuotas(tester);

      await escribirCuota(tester, 0, '1.000,50');
      expect(find.text('Se ajustó'), findsNWidgets(2));
      expect(botonApagado(tester), isFalse);
    });
  });

  group('30A-02C · la cuota supera el saldo', () {
    testWidgets(
      'dada una cuota de \$ 2.600, cuando se escribe, se marca con el saldo, las otras quedan en \$ 0 y el botón se apaga',
      (tester) async {
        await montarCuotas(tester);

        await escribirCuota(tester, 0, '2600');

        expect(find.text('El saldo es \$ 2.500: la cuota no puede ser mayor.'), findsOneWidget);
        expect([textoDeCuota(tester, 1), textoDeCuota(tester, 2)], ['\$ 0', '\$ 0']);
        expect(botonApagado(tester), isTrue);
      },
    );

    testWidgets('dado el error, cuando se corrige el monto, el aviso se va y el botón vuelve', (
      tester,
    ) async {
      await montarCuotas(tester);
      await escribirCuota(tester, 0, '2600');

      await escribirCuota(tester, 0, '1000');

      expect(find.textContaining('la cuota no puede ser mayor'), findsNothing);
      expect(botonApagado(tester), isFalse);
      expect([textoDeCuota(tester, 1), textoDeCuota(tester, 2)], ['\$ 750', '\$ 750']);
    });

    testWidgets(
      'dado un campo vacío o con letras, cuando se escribe, pide el monto y no deja crear',
      (tester) async {
        await montarCuotas(tester);

        await escribirCuota(tester, 1, '');
        expect(find.text('Ingresá el monto de la cuota.'), findsOneWidget);
        expect(botonApagado(tester), isTrue);

        await escribirCuota(tester, 1, 'abc');
        expect(find.text('Ingresá el monto de la cuota.'), findsOneWidget);
        expect(botonApagado(tester), isTrue);
      },
    );

    testWidgets(
      'dada una cuota que se queda con todo, cuando siguen otras, avisa que hay que dejar algo',
      (tester) async {
        await montarCuotas(tester);

        await escribirCuota(tester, 0, '2500');

        expect(find.textContaining('Dejá algo para las cuotas que siguen'), findsOneWidget);
        expect(botonApagado(tester), isTrue);
      },
    );
  });

  group('30A-03 · primera cuota en el pasado', () {
    testWidgets(
      'dada una primera cuota de antes de hoy, cuando se elige, se marca y el botón se apaga',
      (tester) async {
        await montarCuotas(tester);

        await tocarEnCuotas(tester, find.byKey(const Key('cuotas_primera')));
        await tester.tap(find.text('20'));
        await asentarAgendar(tester, 3);
        await tester.tap(find.text('OK'));
        await asentarAgendar(tester);

        expect(find.text('Martes 20/10'), findsOneWidget);
        expect(find.text('La primera cuota tiene que ser hoy o más adelante.'), findsOneWidget);
        expect(botonApagado(tester), isTrue);
      },
    );

    testWidgets('dada una primera cuota futura, cuando se elige, las fechas la siguen', (
      tester,
    ) async {
      await montarCuotas(tester);

      await tocarEnCuotas(tester, find.byKey(const Key('cuotas_primera')));
      await tester.tap(find.text('30'));
      await asentarAgendar(tester, 3);
      await tester.tap(find.text('OK'));
      await asentarAgendar(tester);

      expect(find.text('1 · vie 30/10'), findsOneWidget);
      expect(find.text('2 · vie 06/11'), findsOneWidget);
      expect(find.text('La primera cuota tiene que ser hoy o más adelante.'), findsNothing);
    });

    testWidgets('dado el calendario abierto, cuando se cancela, no cambia nada', (tester) async {
      await montarCuotas(tester);

      await tocarEnCuotas(tester, find.byKey(const Key('cuotas_primera')));
      await tester.tap(find.text('Cancel'));
      await asentarAgendar(tester);

      expect(find.text('Lunes 26/10'), findsOneWidget);
    });
  });

  group('30A-08 · error al crear', () {
    testWidgets(
      'dada una falla al guardar, cuando se crea, avisa que no se agendó ninguna cobranza, conserva lo escrito y el botón pasa a «Reintentar»',
      (tester) async {
        final arnes = await montarCuotas(tester);
        arnes.plan.fallaAlCrear = const FailurePlanNoGuardado(causa: 'x');
        await escribirCuota(tester, 0, '900');

        await tocarEnCuotas(tester, botonPrincipal);

        expect(
          find.text('No pudimos crear el plan. No se agendó ninguna cobranza.'),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsOneWidget);
        expect(botonApagado(tester), isFalse, reason: 'el botón vuelve a habilitarse');
        expect(textoDeCuota(tester, 0), '900');
        expect(paginaPlan, findsOneWidget);
        expect(arnes.telefono.recordatorios.programados, isEmpty);
      },
    );

    testWidgets('dada la falla, cuando se reintenta, usa los mismos ids de cita y sale bien', (
      tester,
    ) async {
      final arnes = await montarCuotas(tester);
      arnes.plan.fallaAlCrear = const FailurePlanNoGuardado(causa: 'x');
      await tocarEnCuotas(tester, botonPrincipal);
      final primeros = arnes.plan.ultimoPlan!.cuotas.map((c) => c.agendaId).toList();

      await tocarEnCuotas(tester, botonPrincipal);

      expect(arnes.plan.pedidosDeCrear, 2);
      expect(arnes.plan.ultimoPlan!.cuotas.map((c) => c.agendaId), primeros);
      expect(arnes.ids, hasLength(3), reason: 'no se generaron ids de más');
      expect(paginaLista, findsOneWidget);
    });

    testWidgets(
      'dada una regla que el servidor local rechaza, cuando se crea, muestra su aviso y deja corregir',
      (tester) async {
        final arnes = await montarCuotas(tester);
        arnes.plan.fallaAlCrear = const FailurePlanDeCuotas(MotivoPlanDeCuotas.montos);

        await tocarEnCuotas(tester, botonPrincipal);

        expect(
          find.text(const FailurePlanDeCuotas(MotivoPlanDeCuotas.montos).mensaje),
          findsOneWidget,
        );
        expect(botonApagado(tester), isFalse);
      },
    );

    testWidgets('dada la falla, cuando se cambia algo, el aviso viejo se va', (tester) async {
      final arnes = await montarCuotas(tester);
      arnes.plan.fallaAlCrear = const FailurePlanNoGuardado(causa: 'x');
      await tocarEnCuotas(tester, botonPrincipal);

      await tocarEnCuotas(tester, find.byKey(const Key('cuotas_mas')));

      expect(find.textContaining('No pudimos crear el plan'), findsNothing);
      expect(find.text('Crear plan'), findsOneWidget);
    });
  });

  group('casos límite', () {
    testWidgets(
      'dado un doble toque en «Crear plan» con el guardado en vuelo, cuando se toca dos veces, se crea una sola vez y el botón avisa',
      (tester) async {
        final arnes = await montarCuotas(tester);
        arnes.plan.retenerElCrear = Completer<void>();

        await tester.tap(botonPrincipal);
        await tester.pump();
        await tester.tap(botonPrincipal, warnIfMissed: false);
        await tester.pump();

        expect(arnes.plan.pedidosDeCrear, 1);
        expect(find.text('Creando…'), findsOneWidget);
        expect(elBotonPrincipal(tester).onPressed, isNull);

        arnes.plan.retenerElCrear!.complete();
        await asentarAgendar(tester);
        expect(arnes.plan.pedidosDeCrear, 1);
        expect(paginaLista, findsOneWidget);
      },
    );

    testWidgets('dado un guardado en vuelo, cuando se toca atrás o el contador, no responde', (
      tester,
    ) async {
      final arnes = await montarCuotas(tester);
      arnes.plan.retenerElCrear = Completer<void>();
      await tester.tap(botonPrincipal);
      await tester.pump();

      expect(tester.widget<IconButton>(find.byKey(const Key('cuotas_mas'))).onPressed, isNull);
      expect(
        find.byKey(const Key('venta_atras')),
        findsNothing,
        reason: 'sin salida mientras guarda',
      );

      arnes.plan.retenerElCrear!.complete();
      await asentarAgendar(tester);
    });

    testWidgets(
      'dado lo escrito, cuando se toca ✕, pregunta y «Descartar» vuelve con false; al reentrar empieza de cero',
      (tester) async {
        final arnes = await montarCuotas(tester);
        await tocarEnCuotas(tester, find.byKey(const Key('cuotas_mas')));
        await escribirCuota(tester, 0, '900');

        await tocarEnCuotas(tester, volverDeCuotas);
        expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
        await tester.tap(find.text('Descartar'));
        await asentarAgendar(tester);

        expect(arnes.resultados, [false]);
        expect(paginaPlan, findsNothing);
        expect(arnes.plan.pedidosDeCrear, 0);

        await abrirCuotas(tester);
        expect(find.byKey(const Key('cuotas_cantidad')), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(
          [for (var i = 0; i < 3; i++) textoDeCuota(tester, i)],
          ['\$ 833', '\$ 833', '\$ 834'],
        );
      },
    );

    testWidgets('dado «Seguir escribiendo», cuando se pregunta, no se pierde nada', (tester) async {
      await montarCuotas(tester);
      await escribirCuota(tester, 0, '900');

      await tocarEnCuotas(tester, volverDeCuotas);
      await tester.tap(find.text('Seguir escribiendo'));
      await asentarAgendar(tester);

      expect(paginaPlan, findsOneWidget);
      expect(textoDeCuota(tester, 0), '900');
    });

    testWidgets('dado nada escrito, cuando se toca ✕, cierra directo con false', (tester) async {
      final arnes = await montarCuotas(tester);

      await tocarEnCuotas(tester, volverDeCuotas);

      expect(find.text('¿Descartar lo que escribiste?'), findsNothing);
      expect(arnes.resultados, [false]);
    });

    testWidgets('dado el atrás del sistema, cuando hay algo escrito, también pregunta', (
      tester,
    ) async {
      await montarCuotas(tester);
      await escribirCuota(tester, 0, '900');

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
    });

    testWidgets(
      'dada letra al 200 % en un teléfono chico, cuando se arma el plan de 12 cuotas, no desborda y se puede crear',
      (tester) async {
        final arnes = await montarCuotas(tester, escala: 2, tamano: const Size(320, 568));

        for (var i = 0; i < 9; i++) {
          await tocarEnCuotas(tester, find.byKey(const Key('cuotas_mas')));
        }
        expect(find.byKey(const Key('cuotas_cantidad')), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.text('12'), findsOneWidget);

        await escribirCuota(tester, 11, '10');
        await tocarEnCuotas(tester, botonPrincipal);
        expect(tester.takeException(), isNull);
        expect(arnes.plan.ultimoPlan!.cuotas, hasLength(12));
      },
    );

    testWidgets(
      'dada letra al 200 %, cuando se muestra el error de una cuota, se lee entero y no desborda',
      (tester) async {
        await montarCuotas(tester, escala: 2, tamano: const Size(320, 568));

        await escribirCuota(tester, 0, '2600');

        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('la cuota no puede ser mayor', skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets('dado un saldo grande, cuando se reparte, los montos con miles se ven con punto', (
      tester,
    ) async {
      await montarCuotas(tester, plan: PlanDeCuotasEnMemoria(montoCentavos: 123456700));

      expect(find.textContaining('saldo \$ 1.234.567'), findsOneWidget);
      expect(textoDeCuota(tester, 0), '\$ 411.522');
    });
  });

  group('estados de la lectura', () {
    testWidgets('dado que se está leyendo el plan, cuando se abre, muestra el esqueleto', (
      tester,
    ) async {
      final lectura = Completer<void>();
      await montarCuotas(
        tester,
        plan: PlanDeCuotasEnMemoria()..retenerLaLectura = lectura,
        abrir: false,
      );
      await tester.tap(find.text('abrir cuotas'));
      await asentarAgendar(tester);
      expect(find.byKey(const Key('cuotas_cargando')), findsOneWidget);
      expect(find.text('Crear plan'), findsNothing);

      lectura.complete();
      await asentarAgendar(tester);
      expect(find.byKey(const Key('cuotas_cargando')), findsNothing);
      expect(find.text('Crear plan'), findsOneWidget);
    });

    testWidgets('dado que no se puede leer, cuando se abre, avisa y «Reintentar» vuelve a leer', (
      tester,
    ) async {
      final arnes = await montarCuotas(tester, plan: PlanDeCuotasEnMemoria()..fallaAlLeer = true);

      expect(find.text('No pudimos leer las cuotas guardadas en tu teléfono.'), findsOneWidget);
      expect(find.byKey(const Key('cuotas_fila_0')), findsNothing);

      arnes.plan.fallaAlLeer = false;
      await tocarEnCuotas(tester, find.text('Reintentar'));
      expect(find.byKey(const Key('cuotas_fila_0')), findsOneWidget);
    });

    testWidgets('dada una venta que ya no está, cuando se abre, lo dice y deja volver', (
      tester,
    ) async {
      final arnes = await montarCuotas(tester, plan: PlanDeCuotasEnMemoria()..ventaAusente = true);

      expect(find.byKey(const Key('cuotas_sin_venta')), findsOneWidget);
      await tocarEnCuotas(tester, find.text('Volver'));
      expect(arnes.resultados, [false]);
    });

    testWidgets(
      'dada una venta sin saldo (30A-07), cuando se abre, dice que no hay nada que repartir',
      (tester) async {
        await montarCuotas(
          tester,
          plan: PlanDeCuotasEnMemoria(montoCentavos: 450000, cobradoCentavos: 450000),
        );

        expect(find.text('La venta está pagada'), findsOneWidget);
        expect(find.text('No hay saldo para repartir en cuotas.'), findsOneWidget);
        expect(find.text('Crear plan'), findsNothing);
      },
    );

    testWidgets(
      'dada una venta que ya tiene cuotas por cobrar, cuando se abre, manda a la lista en vez de armar otro plan',
      (tester) async {
        await montarCuotas(
          tester,
          plan: PlanDeCuotasEnMemoria(
            cuotas: [cuotaDe(1, dia: 2, monto: 125000), cuotaDe(2, dia: 9, monto: 125000)],
          ),
        );

        expect(find.byKey(const Key('cuotas_ya_armado')), findsOneWidget);
        expect(find.text('Crear plan'), findsNothing);
        await tocarEnCuotas(tester, find.text('Ver las cuotas'));
        expect(paginaLista, findsOneWidget);
      },
    );

    testWidgets(
      'dada una venta con 11 cuotas en el servidor, cuando se arma, el contador no deja pasar de 12',
      (tester) async {
        await montarCuotas(
          tester,
          plan: PlanDeCuotasEnMemoria(
            montoCentavos: 5000000,
            cobradoCentavos: 1000000,
            cuotas: [
              for (var i = 1; i <= 10; i++) cuotaDe(i, dia: i, monto: 100000, cubierta: true),
            ],
          ),
        );

        // 10 cuotas ya cerradas: caben 2 más (el tope del servidor es 12 por venta).
        expect(find.byKey(const Key('cuotas_cantidad')), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(tester.widget<IconButton>(find.byKey(const Key('cuotas_mas'))).onPressed, isNull);
      },
    );
  });
}

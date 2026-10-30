// Las reglas puras del plan de cuotas (HU-COB-004, #166): el reparto de «Reparto» (Cristian, 23/10) y
// a qué cuota va cada pago («Plan cuotas»). Sin pantalla ni base.
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cuota.dart';
import 'package:colportores_mobile/features/cobranzas/domain/services/reparto_de_cuotas.dart';
import 'package:test/test.dart';

CitaDeCuota cita(
  String id,
  int dia,
  int monto, {
  EstadoAgenda estado = EstadoAgenda.programada,
  DateTime? creada,
}) => CitaDeCuota(
  agendaId: id,
  fecha: DateTime(2026, 10, dia, 10),
  montoCentavos: monto,
  estado: estado,
  creadaEn: creada ?? DateTime.utc(2026, 10, 20),
);

CobroDelPlan cobro(
  int monto, {
  DateTime? creado,
  DateTime? fecha,
  MedioCobranza medio = MedioCobranza.efectivo,
}) => CobroDelPlan(
  montoCentavos: monto,
  creadoEn: creado ?? DateTime.utc(2026, 10, 21),
  fecha: fecha,
  medio: medio,
);

void main() {
  group('partesIguales', () {
    test(
      'dado \$ 2.500 en 3 cuotas, cuando se reparte, la diferencia del redondeo va en la última',
      () {
        expect(RepartoDeCuotas.partesIguales(250000, 3), [83300, 83300, 83400]);
      },
    );

    test('dado un total que se divide justo, cuando se reparte, todas valen lo mismo', () {
      expect(RepartoDeCuotas.partesIguales(150000, 3), [50000, 50000, 50000]);
    });

    test('dado \$ 2.500 en 2 cuotas, cuando se reparte, son dos mitades (30A-02)', () {
      expect(RepartoDeCuotas.partesIguales(250000, 2), [125000, 125000]);
    });

    test(
      'dado un saldo con centavos, cuando se reparte, las primeras son pesos enteros y la última lleva el resto',
      () {
        expect(RepartoDeCuotas.partesIguales(250050, 3), [83300, 83300, 83450]);
      },
    );

    test(
      'dado un saldo que no llega a un peso por cuota, cuando se reparte, lo hace en centavos',
      () {
        expect(RepartoDeCuotas.partesIguales(250, 3), [83, 83, 84]);
      },
    );

    test('dada una sola cuota, cuando se reparte, lleva todo', () {
      expect(RepartoDeCuotas.partesIguales(700, 1), [700]);
    });

    test('dada una cantidad menor que uno, cuando se reparte, no hay cuotas', () {
      expect(RepartoDeCuotas.partesIguales(700, 0), isEmpty);
    });

    test('dado un total menor que la cantidad, cuando se reparte, la última lleva todo', () {
      expect(RepartoDeCuotas.partesIguales(2, 3), [0, 0, 2]);
    });
  });

  group('fechas', () {
    test(
      'dado un plan semanal, cuando se arman las fechas, cada cuota es 7 días después, a las 10:00',
      () {
        final fechas = RepartoDeCuotas.fechas(
          primera: DateTime(2026, 10, 26),
          cantidad: 3,
          frecuencia: FrecuenciaDeCuotas.semanal,
        );
        expect(fechas, [
          DateTime(2026, 10, 26, 10),
          DateTime(2026, 11, 2, 10),
          DateTime(2026, 11, 9, 10),
        ]);
      },
    );

    test(
      'dado un plan mensual, cuando se arman las fechas, cada cuota es el mismo día del mes siguiente',
      () {
        final fechas = RepartoDeCuotas.fechas(
          primera: DateTime(2026, 10, 26),
          cantidad: 3,
          frecuencia: FrecuenciaDeCuotas.mensual,
        );
        expect(fechas, [
          DateTime(2026, 10, 26, 10),
          DateTime(2026, 11, 26, 10),
          DateTime(2026, 12, 26, 10),
        ]);
      },
    );

    test(
      'dado un plan mensual desde el 31, cuando el mes no llega al 31, cae en su último día y vuelve al 31',
      () {
        final fechas = RepartoDeCuotas.fechas(
          primera: DateTime(2026, 1, 31),
          cantidad: 4,
          frecuencia: FrecuenciaDeCuotas.mensual,
        );
        expect(fechas.map((f) => (f.month, f.day)), [(1, 31), (2, 28), (3, 31), (4, 30)]);
      },
    );

    test('dado un plan mensual que cruza el año, cuando se arman las fechas, sigue en enero', () {
      final fechas = RepartoDeCuotas.fechas(
        primera: DateTime(2026, 12, 15),
        cantidad: 3,
        frecuencia: FrecuenciaDeCuotas.mensual,
      );
      expect(fechas.map((f) => (f.year, f.month, f.day)), [
        (2026, 12, 15),
        (2027, 1, 15),
        (2027, 2, 15),
      ]);
    });

    test('dadas fechas armadas, cuando se deduce la frecuencia, la reconoce', () {
      Cuota c(int n, DateTime f) => Cuota(
        agendaId: 'a$n',
        numero: n,
        fecha: f,
        montoCentavos: 100,
        estado: EstadoAgenda.programada,
      );
      expect(
        RepartoDeCuotas.deducirFrecuencia([
          c(1, DateTime(2026, 10, 26, 10)),
          c(2, DateTime(2026, 11, 2, 10)),
        ]),
        FrecuenciaDeCuotas.semanal,
      );
      expect(
        RepartoDeCuotas.deducirFrecuencia([
          c(1, DateTime(2026, 10, 26, 10)),
          c(2, DateTime(2026, 11, 26, 10)),
        ]),
        FrecuenciaDeCuotas.mensual,
      );
      expect(
        RepartoDeCuotas.deducirFrecuencia([
          c(1, DateTime(2026, 10, 26, 10)),
          c(2, DateTime(2026, 11, 3, 10)),
        ]),
        isNull,
      );
      expect(RepartoDeCuotas.deducirFrecuencia([c(1, DateTime(2026, 10, 26, 10))]), isNull);
    });
  });

  group('reajustar', () {
    final iguales = RepartoDeCuotas.partesIguales(250000, 3);

    test(
      'dada la primera cuota subida a \$ 900, cuando se reajusta, las otras dos se reparten \$ 1.600 y se marcan (30A-02B)',
      () {
        final r = RepartoDeCuotas.reajustar(
          montos: iguales,
          indice: 0,
          nuevoMonto: 90000,
          saldo: 250000,
        );
        expect(r.montos, [90000, 80000, 80000]);
        expect(r.ajustadas, {1, 2});
        expect(r.esValido, isTrue);
      },
    );

    test(
      'dada la segunda cuota cambiada, cuando se reajusta, la primera no se toca y la tercera lleva lo que queda',
      () {
        final r = RepartoDeCuotas.reajustar(
          montos: iguales,
          indice: 1,
          nuevoMonto: 100000,
          saldo: 250000,
        );
        expect(r.montos, [83300, 100000, 66700]);
        expect(r.ajustadas, {2});
      },
    );

    test('dada la última cuota cambiada, cuando se reajusta, no hay a quién ajustar', () {
      final r = RepartoDeCuotas.reajustar(
        montos: iguales,
        indice: 2,
        nuevoMonto: 50000,
        saldo: 250000,
      );
      expect(r.montos, [83300, 83300, 50000]);
      expect(r.ajustadas, isEmpty);
      expect(r.esValido, isTrue);
    });

    test(
      'dada una cuota mayor al saldo, cuando se reajusta, se marca y las que siguen quedan en cero (30A-02C)',
      () {
        final r = RepartoDeCuotas.reajustar(
          montos: iguales,
          indice: 0,
          nuevoMonto: 260000,
          saldo: 250000,
        );
        expect(r.problemas, {0: ProblemaDeCuota.superaElSaldo});
        expect(r.montos, [260000, 0, 0]);
        expect(r.esValido, isFalse);
      },
    );

    test('dada una cuota en cero, cuando se reajusta, no tiene monto', () {
      final r = RepartoDeCuotas.reajustar(montos: iguales, indice: 1, nuevoMonto: 0, saldo: 250000);
      expect(r.problemas, {1: ProblemaDeCuota.sinMonto});
    });

    test(
      'dada una cuota que se queda con todo el saldo, cuando siguen otras, no les deja ni un peso',
      () {
        final r = RepartoDeCuotas.reajustar(
          montos: iguales,
          indice: 0,
          nuevoMonto: 250000,
          saldo: 250000,
        );
        expect(r.problemas, {0: ProblemaDeCuota.noDejaParaLasSiguientes});
      },
    );

    test(
      'dada la última cuota que hace pasar el saldo a las anteriores, cuando se reajusta, supera el saldo',
      () {
        final r = RepartoDeCuotas.reajustar(
          montos: iguales,
          indice: 2,
          nuevoMonto: 100000,
          saldo: 250000,
        );
        expect(r.problemas, {2: ProblemaDeCuota.superaElSaldo});
      },
    );

    test('dada una cuota con \$ 400 ya cobrados, cuando se baja de ahí, no se deja', () {
      final r = RepartoDeCuotas.reajustar(
        montos: [100000, 100000],
        indice: 0,
        nuevoMonto: 30000,
        saldo: 200000,
        pagados: [40000, 0],
      );
      expect(r.problemas, {0: ProblemaDeCuota.menorQueLoPagado});
    });
  });

  test(
    'montosValidos: de 2 a 12 cuotas, con monto, ninguna mayor al saldo y entre todas no más',
    () {
      expect(RepartoDeCuotas.montosValidos([83300, 83300, 83400], 250000), isTrue);
      expect(RepartoDeCuotas.montosValidos([250000], 250000), isFalse, reason: 'menos de 2');
      expect(
        RepartoDeCuotas.montosValidos(List.filled(13, 10), 1000),
        isFalse,
        reason: 'más de 12',
      );
      expect(RepartoDeCuotas.montosValidos([100, 0], 1000), isFalse, reason: 'una sin monto');
      expect(
        RepartoDeCuotas.montosValidos([600, 600], 1000),
        isFalse,
        reason: 'juntas pasan el saldo',
      );
      expect(
        RepartoDeCuotas.montosValidos([1100, 100], 1000),
        isFalse,
        reason: 'una pasa el saldo',
      );
      expect(
        RepartoDeCuotas.montosValidos([400, 400], 1000),
        isTrue,
        reason: 'queda saldo sin plan',
      );
    },
  );

  group('estadoDe', () {
    final plan = [cita('a1', 26, 83300), cita('a2', 28, 83300), cita('a3', 30, 83400)];

    test('dado un plan sin cobros, cuando se arma, ninguna cuota tiene nada pagado', () {
      final e = RepartoDeCuotas.estadoDe(citas: plan, cobros: const []);
      expect(e.cuotas.map((c) => (c.numero, c.pagadoCentavos)), [(1, 0), (2, 0), (3, 0)]);
      expect(e.aCerrar, isEmpty);
    });

    test(
      'dado un cobro de \$ 300 en una cuota de \$ 833, cuando se arma, la cuota sigue activa con lo que falta',
      () {
        final e = RepartoDeCuotas.estadoDe(citas: plan, cobros: [cobro(30000)]);
        expect(e.cuotas.first.pagadoCentavos, 30000);
        expect(e.cuotas.first.faltanCentavos, 53300);
        expect(e.cuotas.first.estaCubierta, isFalse);
        expect(e.aCerrar, isEmpty);
      },
    );

    test(
      'dado un cobro igual a la cuota, cuando se arma, la cuota queda cubierta y para cerrar',
      () {
        final e = RepartoDeCuotas.estadoDe(citas: plan, cobros: [cobro(83300)]);
        expect(e.cuotas.first.estaCubierta, isTrue);
        expect(e.aCerrar, ['a1']);
        expect(e.cuotas[1].pagadoCentavos, 0);
      },
    );

    test(
      'dado un pago de más, cuando se arma, completa una cuota y adelanta la siguiente (30A-05)',
      () {
        final e = RepartoDeCuotas.estadoDe(citas: plan, cobros: [cobro(100000)]);
        expect(e.aCerrar, ['a1']);
        expect(e.cuotas[1].pagadoCentavos, 16700);
      },
    );

    test('dados dos cobros que juntos cubren una cuota, cuando se arma, la cubren', () {
      final e = RepartoDeCuotas.estadoDe(
        citas: plan,
        cobros: [
          cobro(40000),
          cobro(43300, creado: DateTime.utc(2026, 10, 22)),
        ],
      );
      expect(e.aCerrar, ['a1']);
    });

    test('dada una cuota ya cubierta y guardada, cuando se arma, no se descuenta dos veces', () {
      final citas = [
        cita('a1', 26, 83300, estado: EstadoAgenda.cumplida),
        cita('a2', 28, 83300),
        cita('a3', 30, 83400),
      ];
      final e = RepartoDeCuotas.estadoDe(citas: citas, cobros: [cobro(83300 + 10000)]);
      expect(e.cuotas.first.estaCubierta, isTrue);
      expect(e.cuotas[1].pagadoCentavos, 10000);
      expect(e.aCerrar, isEmpty);
    });

    test(
      'dada una cuota cubierta por un cobro en efectivo, cuando se arma, dice el día del cobro y el medio',
      () {
        final dia = DateTime.utc(2026, 10, 26, 15);
        final e = RepartoDeCuotas.estadoDe(
          citas: plan,
          cobros: [cobro(83300, fecha: dia)],
        );
        expect(e.cuotas.first.cubiertaEl, dia);
        expect(e.cuotas.first.medios, [MedioCobranza.efectivo]);
        expect(e.cuotas[1].cubiertaEl, isNull);
        expect(e.cuotas[1].medios, isEmpty);
      },
    );

    test(
      'dada una cuota cubierta por dos cobros de medios distintos, cuando se arma, dice el día del que la completó y los dos medios',
      () {
        final primero = DateTime.utc(2026, 10, 24, 15);
        final segundo = DateTime.utc(2026, 10, 27, 15);
        final e = RepartoDeCuotas.estadoDe(
          citas: plan,
          cobros: [
            cobro(40000, creado: DateTime.utc(2026, 10, 24, 16), fecha: primero),
            cobro(
              43300,
              creado: DateTime.utc(2026, 10, 27, 16),
              fecha: segundo,
              medio: MedioCobranza.tarjeta,
            ),
          ],
        );
        expect(e.cuotas.first.cubiertaEl, segundo);
        expect(e.cuotas.first.medios, [MedioCobranza.efectivo, MedioCobranza.tarjeta]);
      },
    );

    test(
      'dados dos cobros que cubren una cuota y adelantan la siguiente, cuando se arma, la cubierta solo cuenta lo que usó',
      () {
        final e = RepartoDeCuotas.estadoDe(
          citas: plan,
          cobros: [
            cobro(50000, creado: DateTime.utc(2026, 10, 22), fecha: DateTime.utc(2026, 10, 22, 15)),
            cobro(
              50000,
              creado: DateTime.utc(2026, 10, 23),
              fecha: DateTime.utc(2026, 10, 23, 15),
              medio: MedioCobranza.transferencia,
            ),
          ],
        );
        expect(e.cuotas.first.cubiertaEl, DateTime.utc(2026, 10, 23, 15));
        expect(e.cuotas.first.medios, [MedioCobranza.efectivo, MedioCobranza.transferencia]);
        expect(e.cuotas[1].pagadoCentavos, 16700);
        expect(e.cuotas[1].medios, isEmpty);
      },
    );

    test(
      'dada una cuota cerrada que los cobros no cubren, cuando se arma, queda pagada sin día ni medio',
      () {
        final citas = [cita('a1', 26, 83300, estado: EstadoAgenda.cumplida), cita('a2', 28, 83300)];
        final e = RepartoDeCuotas.estadoDe(citas: citas, cobros: const []);
        expect(e.cuotas.first.estaCubierta, isTrue);
        expect(e.cuotas.first.cubiertaEl, isNull);
        expect(e.cuotas.first.medios, isEmpty);
      },
    );

    test(
      'dado un plan anterior ya cumplido, cuando se arma el plan nuevo, las cuotas viejas no consumen los cobros del nuevo',
      () {
        final viejo = DateTime.utc(2026, 9, 1);
        final citas = [
          cita('v1', 5, 100000, estado: EstadoAgenda.cumplida, creada: viejo),
          cita('n1', 26, 75000),
          cita('n2', 28, 75000),
        ];
        final e = RepartoDeCuotas.estadoDe(citas: citas, cobros: [cobro(75000)]);
        expect(e.cuotas.map((c) => c.agendaId), ['v1', 'n1', 'n2']);
        expect(e.cuotas[1].estaCubierta, isTrue);
        expect(e.cuotas[2].pagadoCentavos, 0);
        expect(e.aCerrar, ['n1']);
        expect(e.cuotas[0].cubiertaEl, isNull);
      },
    );

    test('dados cobros anteriores al plan, cuando se arma, no cuentan para las cuotas', () {
      final e = RepartoDeCuotas.estadoDe(
        citas: plan,
        cobros: [cobro(100000, creado: DateTime.utc(2026, 10, 19))],
      );
      expect(e.cuotas.every((c) => c.pagadoCentavos == 0), isTrue);
      expect(e.aCerrar, isEmpty);
    });

    test(
      'dada una cuota cancelada, cuando se arma, deja de ser cuota y las demás se renumeran',
      () {
        final citas = [
          cita('a1', 26, 83300),
          cita('a2', 28, 83300, estado: EstadoAgenda.cancelada),
          cita('a3', 30, 83400),
        ];
        final e = RepartoDeCuotas.estadoDe(citas: citas, cobros: const []);
        expect(e.cuotas.map((c) => (c.agendaId, c.numero)), [('a1', 1), ('a3', 2)]);
      },
    );

    test('dadas las citas en desorden, cuando se arma, las ordena por fecha', () {
      final e = RepartoDeCuotas.estadoDe(citas: [plan[2], plan[0], plan[1]], cobros: const []);
      expect(e.cuotas.map((c) => c.agendaId), ['a1', 'a2', 'a3']);
    });

    test('dado todo cobrado, cuando se arma, todas quedan cubiertas', () {
      final e = RepartoDeCuotas.estadoDe(citas: plan, cobros: [cobro(250000)]);
      expect(e.cuotas.every((c) => c.estaCubierta), isTrue);
      expect(e.aCerrar, ['a1', 'a2', 'a3']);
    });
  });

  group('aplicarPago', () {
    Cuota c(int n, int monto, {int pagado = 0, bool cubierta = false}) => Cuota(
      agendaId: 'a$n',
      numero: n,
      fecha: DateTime(2026, 11, n, 10),
      montoCentavos: monto,
      estado: cubierta ? EstadoAgenda.cumplida : EstadoAgenda.programada,
      pagadoCentavos: pagado,
    );

    test(
      'dado un pago de \$ 1.000 con la cuota 2 faltándole \$ 433, cuando se aplica, completa la 2 y adelanta \$ 567 de la 3 (30A-05)',
      () {
        final pago = RepartoDeCuotas.aplicarPago([
          c(1, 83300, cubierta: true),
          c(2, 83300, pagado: 40000),
          c(3, 83400),
        ], 100000);
        expect(pago.primeraCuota, 2);
        expect(pago.completadas.map((p) => p.cuota.numero), [2]);
        expect(pago.completadas.single.aplicadoCentavos, 43300);
        expect(pago.adelanto?.cuota.numero, 3);
        expect(pago.adelanto?.aplicadoCentavos, 56700);
        expect(pago.sobranteCentavos, 0);
      },
    );

    test('dado un pago menor a la cuota, cuando se aplica, la deja activa con lo que falta', () {
      final pago = RepartoDeCuotas.aplicarPago([c(1, 50000)], 30000);
      expect(pago.completadas, isEmpty);
      expect(pago.adelanto?.faltaDespuesCentavos, 20000);
    });

    test(
      'dado un pago mayor a todas las cuotas, cuando se aplica, lo que sobra queda como pago libre',
      () {
        final pago = RepartoDeCuotas.aplicarPago([c(1, 50000)], 70000);
        expect(pago.completadas.single.aplicadoCentavos, 50000);
        expect(pago.sobranteCentavos, 20000);
        expect(pago.adelanto, isNull);
      },
    );

    test('dado un plan sin cuotas abiertas, cuando se aplica, el pago es libre', () {
      final pago = RepartoDeCuotas.aplicarPago([c(1, 50000, cubierta: true)], 70000);
      expect(pago.esVacia, isTrue);
      expect(pago.primeraCuota, isNull);
      expect(pago.sobranteCentavos, 70000);
    });
  });

  group('situacion de una cuota', () {
    final ahora = DateTime(2026, 11, 2, 15);
    Cuota c(DateTime fecha, {int pagado = 0, EstadoAgenda e = EstadoAgenda.programada}) => Cuota(
      agendaId: 'a',
      numero: 1,
      fecha: fecha,
      montoCentavos: 1000,
      estado: e,
      pagadoCentavos: pagado,
    );

    test('la cuota de hoy a una hora que ya pasó todavía no venció', () {
      expect(c(DateTime(2026, 11, 2, 10)).situacion(ahora), SituacionDeCuota.agendada);
    });

    test('la cuota de ayer sin cubrir venció, también con un pago parcial', () {
      expect(c(DateTime(2026, 11, 1, 10)).situacion(ahora), SituacionDeCuota.vencida);
      expect(c(DateTime(2026, 11, 1, 10), pagado: 400).situacion(ahora), SituacionDeCuota.vencida);
    });

    test('una cuota con algo pagado y a tiempo es parcial; cubierta, pagada', () {
      expect(c(DateTime(2026, 11, 9, 10), pagado: 400).situacion(ahora), SituacionDeCuota.parcial);
      expect(
        c(DateTime(2026, 11, 1, 10), e: EstadoAgenda.cumplida).situacion(ahora),
        SituacionDeCuota.pagada,
      );
    });
  });
}

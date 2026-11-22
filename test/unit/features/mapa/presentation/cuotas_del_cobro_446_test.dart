// La tercera línea de la fila de un cobro en el Historial de la casa (vista 39, C·03, #446; decisión
// del 10/11, P1 del QA de #677): con plan, las cuotas que cubrió el cobro, calculadas con los cobros
// de la venta hasta ese y en orden (`RepartoDeCuotas.cuotasDeCadaCobro`); sin plan, «Venta 0038».
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/services/reparto_de_cuotas.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_historial_de_la_casa.dart';
import 'package:flutter_test/flutter_test.dart';

final _plan = DateTime.utc(2026, 10, 20);

CitaDeCuota _cita(
  int dia,
  int monto, {
  EstadoAgenda estado = EstadoAgenda.programada,
  DateTime? creada,
}) => CitaDeCuota(
  agendaId: 'ag-$dia',
  fecha: DateTime(2026, 10, dia, 10),
  montoCentavos: monto,
  estado: estado,
  creadaEn: creada ?? _plan,
);

CobroDelPlan _cobro(int monto, int hora) =>
    CobroDelPlan(montoCentavos: monto, creadoEn: DateTime.utc(2026, 10, 21, hora));

String? _lineas(List<CitaDeCuota> citas, List<CobroDelPlan> cobros, int cual) {
  final cuotas = RepartoDeCuotas.cuotasDeCadaCobro(citas: citas, cobros: cobros)[cual];
  return FormatoHistorialDeLaCasa.subtitulo(
    CobroDeLaCasa(
      id: 'cob',
      fecha: DateTime.utc(2026, 10, 21),
      montoCentavos: cobros[cual].montoCentavos,
      medio: MedioCobranza.efectivo,
      ventaId: 'ven-1',
      numeroTalonario: '0038',
      cuotas: cuotas,
    ),
  );
}

void main() {
  final dosDe600 = [_cita(25, 60000), _cita(30, 60000)];
  final tresDe800 = [_cita(25, 80000), _cita(28, 80000), _cita(31, 80000)];
  final cuatroDe500 = [_cita(25, 50000), _cita(26, 50000), _cita(27, 50000), _cita(28, 50000)];

  group('cuota completa', () {
    test('dado un plan de 2 cuotas de \$ 600, el primer cobro de \$ 600 dice «Cuota 1 de 2»', () {
      expect(_lineas(dosDe600, [_cobro(60000, 9)], 0), 'Cuota 1 de 2');
    });

    test('dado que la cuota 1 ya se pagó, el segundo cobro dice «Cuota 2 de 2»', () {
      final cobros = [_cobro(60000, 9), _cobro(60000, 10)];

      expect(_lineas(dosDe600, cobros, 0), 'Cuota 1 de 2');
      expect(_lineas(dosDe600, cobros, 1), 'Cuota 2 de 2');
    });

    test('dado una cuota empezada por otro cobro, el que la termina dice «Cuota 1 de 2»', () {
      final cobros = [_cobro(20000, 9), _cobro(40000, 10)];

      expect(_lineas(dosDe600, cobros, 0), 'Parte de la cuota 1 de 2');
      expect(_lineas(dosDe600, cobros, 1), 'Cuota 1 de 2');
    });

    test('dado que los cobros llegaron en otro orden, se reparten por cuándo se registraron', () {
      final cobros = [_cobro(60000, 11), _cobro(60000, 9)];

      expect(_lineas(dosDe600, cobros, 0), 'Cuota 2 de 2');
      expect(_lineas(dosDe600, cobros, 1), 'Cuota 1 de 2');
    });
  });

  group('varias cuotas', () {
    test('dado un cobro que cubre dos, dice «Cuotas 1 y 2 de 3»', () {
      expect(_lineas(tresDe800, [_cobro(160000, 9)], 0), 'Cuotas 1 y 2 de 3');
    });

    test('dado un cobro que cubre tres seguidas, dice «Cuotas 1 a 3 de 4»', () {
      expect(_lineas(cuatroDe500, [_cobro(150000, 9)], 0), 'Cuotas 1 a 3 de 4');
    });

    test('dado un cobro que cubre una y deja la siguiente a medias, nombra las dos', () {
      expect(_lineas(tresDe800, [_cobro(100000, 9)], 0), 'Cuota 1 y parte de la 2 de 3');
    });

    test('dado un cobro que cubre dos y deja la tercera a medias, va con coma (rev 1120, P2)', () {
      final tresDe1000 = [_cita(25, 100000), _cita(28, 100000), _cita(31, 100000)];

      expect(_lineas(tresDe1000, [_cobro(250000, 9)], 0), 'Cuotas 1 y 2, y parte de la 3 de 3');
    });

    test('los números de las cuotas van en orden aunque se hayan cubierto en otro', () {
      const desordenadas = CuotasDeUnCobro(deTotal: 4, completas: [2, 1], aMedias: 3);
      const salteadas = CuotasDeUnCobro(deTotal: 5, completas: [4, 1, 2]);

      expect(FormatoHistorialDeLaCasa.cuotas(desordenadas), 'Cuotas 1 y 2, y parte de la 3 de 4');
      expect(FormatoHistorialDeLaCasa.cuotas(salteadas), 'Cuotas 1, 2 y 4 de 5');
    });

    test('dado un cobro que cubre de más, nombra solo las cuotas del plan', () {
      expect(_lineas(dosDe600, [_cobro(150000, 9)], 0), 'Cuotas 1 y 2 de 2');
    });
  });

  group('parte de una cuota', () {
    test('dado un cobro de \$ 400 sobre la cuota 2 de \$ 800, dice «Parte de la cuota 2 de 3»', () {
      final cobros = [_cobro(80000, 9), _cobro(40000, 10)];

      expect(_lineas(tresDe800, cobros, 1), 'Parte de la cuota 2 de 3');
    });

    test('dado dos partes de la misma cuota, las dos dicen «Parte de la cuota 1 de 2»', () {
      final cobros = [_cobro(10000, 9), _cobro(10000, 10)];

      expect(_lineas(dosDe600, cobros, 0), 'Parte de la cuota 1 de 2');
      expect(_lineas(dosDe600, cobros, 1), 'Parte de la cuota 1 de 2');
    });
  });

  group('sin plan', () {
    test('dado una venta sin citas con monto, el cobro dice «Venta 0038»', () {
      expect(_lineas(const [], [_cobro(60000, 9)], 0), 'Venta 0038');
    });

    test('dado un cobro de antes de armar el plan, no cuenta para el plan: «Venta 0038»', () {
      final cobros = [
        CobroDelPlan(montoCentavos: 60000, creadoEn: DateTime.utc(2026, 10, 19)),
        _cobro(60000, 9),
      ];

      expect(_lineas(dosDe600, cobros, 0), 'Venta 0038');
      expect(_lineas(dosDe600, cobros, 1), 'Cuota 1 de 2');
    });

    test('dado un cobro después de cubrir todo el plan, dice «Venta 0038»', () {
      final cobros = [_cobro(120000, 9), _cobro(10000, 10)];

      expect(_lineas(dosDe600, cobros, 0), 'Cuotas 1 y 2 de 2');
      expect(_lineas(dosDe600, cobros, 1), 'Venta 0038');
    });

    test('dado un plan con todas sus citas canceladas, el cobro dice «Venta 0038»', () {
      final canceladas = [
        _cita(25, 60000, estado: EstadoAgenda.cancelada),
        _cita(30, 60000, estado: EstadoAgenda.cancelada),
      ];

      expect(_lineas(canceladas, [_cobro(60000, 9)], 0), 'Venta 0038');
    });
  });

  group('igual que la vista 30 A (estadoDe)', () {
    test('las canceladas no cuentan en el «de m» ni en el número', () {
      final citas = [
        _cita(25, 60000),
        _cita(27, 60000, estado: EstadoAgenda.cancelada),
        _cita(30, 60000),
      ];
      final cobros = [_cobro(60000, 9), _cobro(60000, 10)];

      expect(_lineas(citas, cobros, 0), 'Cuota 1 de 2');
      expect(_lineas(citas, cobros, 1), 'Cuota 2 de 2');
    });

    test('las cuotas ya cubiertas reciben primero los cobros, como en estadoDe', () {
      final citas = [_cita(25, 60000, estado: EstadoAgenda.cumplida), _cita(30, 60000)];
      final cobros = [_cobro(60000, 9), _cobro(30000, 10)];

      expect(_lineas(citas, cobros, 0), 'Cuota 1 de 2');
      expect(_lineas(citas, cobros, 1), 'Parte de la cuota 2 de 2');
      final estado = RepartoDeCuotas.estadoDe(citas: citas, cobros: cobros);
      expect(estado.cuotas.last.pagadoCentavos, 30000);
    });

    test('una cuota sin monto no la cubre ningún cobro', () {
      final citas = [_cita(25, 0), _cita(30, 60000)];

      expect(_lineas(citas, [_cobro(60000, 9)], 0), 'Cuota 2 de 2');
    });
  });

  test('el lector de pantalla lee la tercera línea del cobro', () {
    final cuotas = RepartoDeCuotas.cuotasDeCadaCobro(
      citas: dosDe600,
      cobros: [_cobro(60000, 9)],
    ).single;
    final evento = CobroDeLaCasa(
      id: 'cob',
      fecha: DateTime.utc(2026, 10, 21, 14, 20),
      montoCentavos: 60000,
      medio: MedioCobranza.efectivo,
      ventaId: 'ven-1',
      numeroTalonario: '0038',
      cuotas: cuotas,
    );

    expect(
      FormatoHistorialDeLaCasa.paraLector(evento, DateTime.utc(2026, 11, 1)),
      endsWith('Cuota 1 de 2'),
    );
  });
}

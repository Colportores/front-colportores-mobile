// Los textos de cada fila de la hoja «Agendados» del mapa (vista 06, 06C·03, #407).
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/vista_agenda.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cuota.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_agendados.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/agenda_items_falsos.dart';

/// [item] con su venta y, si es una cuota, el monto previsto.
ItemAgenda deVenta(ItemAgenda item, {String ventaId = 'v-1', int? montoPrevisto}) {
  final a = item.agenda;
  return ItemAgenda(
    agenda: Agenda(
      id: a.id,
      espacioId: a.espacioId,
      espacioPersonaId: a.espacioPersonaId,
      tipo: a.tipo,
      fechaProgramada: a.fechaProgramada,
      estado: a.estado,
      colportorId: a.colportorId,
      ventaId: ventaId,
      montoPrevistoCentavos: montoPrevisto,
      auditoria: a.auditoria,
    ),
    personaNombre: item.personaNombre,
    personaApellido: item.personaApellido,
    casa: item.casa,
  );
}

PlanDeCuotas plan({int total = 290000, int cobrado = 0, List<Cuota> cuotas = const []}) =>
    PlanDeCuotas(
      venta: VentaConSaldo(
        ventaId: 'v-1',
        numeroTalonario: '0012',
        fecha: DateTime.utc(2026, 10, 1),
        montoTotalCentavos: total,
        cobradoCentavos: cobrado,
      ),
      espacioId: 'esp-1',
      espacioPersonaId: 'ep-1',
      colportorId: 'col-1',
      cuotas: cuotas,
    );

Cuota cuota(String agendaId, int numero, int monto, {int pagado = 0}) => Cuota(
  agendaId: agendaId,
  numero: numero,
  fecha: DateTime(2026, 11, 11, 15),
  montoCentavos: monto,
  estado: EstadoAgenda.programada,
  pagadoCentavos: pagado,
);

void main() {
  final ahora = DateTime(2026, 11, 11, 14, 35);
  final cobranza = itemAgenda('c1', DateTime(2026, 11, 11, 15), tipo: TipoAgenda.cobranza);
  final entrega = itemAgenda('n1', DateTime(2026, 11, 11, 18), tipo: TipoAgenda.entrega);
  final entrevista = itemAgenda('e1', DateTime(2026, 11, 11, 16, 30));

  group('CobroDeAgendado.de', () {
    test('una cuota del plan da su número y lo que le falta (no el monto entero)', () {
      final item = deVenta(cobranza, montoPrevisto: 145000);
      final cobro = CobroDeAgendado.de(
        item,
        plan(cuotas: [cuota('otra', 1, 145000), cuota('c1', 2, 145000, pagado: 20000)]),
      )!;

      expect(cobro.numeroCuota, 2);
      expect(cobro.faltaCentavos, 125000);
    });

    test('una cobranza de una venta sin plan da el saldo de la venta, sin número de cuota', () {
      final cobro = CobroDeAgendado.de(deVenta(cobranza), plan(total: 300000, cobrado: 100000))!;

      expect(cobro.numeroCuota, isNull);
      expect(cobro.faltaCentavos, 200000);
    });

    test('una entrega dice si la venta todavía debe', () {
      expect(CobroDeAgendado.de(deVenta(entrega), plan(cobrado: 1000))!.conSaldo, isTrue);
      expect(CobroDeAgendado.de(deVenta(entrega), plan(cobrado: 290000))!.conSaldo, isFalse);
    });

    test('una entrevista no tiene nada que cobrar', () {
      expect(CobroDeAgendado.de(deVenta(entrevista), plan()), isNull);
    });
  });

  group('FormatoAgendados.detalle (canvas 06C·03)', () {
    test('«Cobranza · 2.ª cuota · \$U 1.450»', () {
      expect(
        FormatoAgendados.detalle(
          cobranza,
          const CobroDeAgendado(numeroCuota: 2, faltaCentavos: 145000),
          atrasada: false,
        ),
        'Cobranza · 2.ª cuota · \$U 1.450',
      );
    });

    test('«Cobranza atrasada · \$U 980»: la atrasada no repite el número de cuota', () {
      expect(
        FormatoAgendados.detalle(
          cobranza,
          const CobroDeAgendado(numeroCuota: 1, faltaCentavos: 98000),
          atrasada: true,
        ),
        'Cobranza atrasada · \$U 980',
      );
    });

    test(
      'sin plan leído, o sin venta, la cobranza dice solo «Cobranza» (no inventa un monto; decisión del 11/11, P1 de #704)',
      () {
        expect(FormatoAgendados.detalle(cobranza, null, atrasada: false), 'Cobranza');
        expect(FormatoAgendados.detalle(cobranza, null, atrasada: true), 'Cobranza atrasada');
      },
    );

    test('una cuota ya cubierta en el plan no muestra «\$U 0»', () {
      expect(
        FormatoAgendados.detalle(
          cobranza,
          const CobroDeAgendado(numeroCuota: 3, faltaCentavos: 0),
          atrasada: false,
        ),
        'Cobranza · 3.ª cuota',
      );
    });

    test('«Entrevista» y «Entrevista atrasada»', () {
      expect(FormatoAgendados.detalle(entrevista, null, atrasada: false), 'Entrevista');
      expect(FormatoAgendados.detalle(entrevista, null, atrasada: true), 'Entrevista atrasada');
    });

    test(
      'la entrega: «Entrega y pago» si la venta debe; «Entrega pendiente» si no; «Entrega» si no '
      'se sabe',
      () {
        expect(
          FormatoAgendados.detalle(entrega, const CobroDeAgendado(conSaldo: true), atrasada: false),
          'Entrega y pago',
        );
        expect(
          FormatoAgendados.detalle(
            entrega,
            const CobroDeAgendado(conSaldo: false),
            atrasada: false,
          ),
          'Entrega pendiente',
        );
        expect(FormatoAgendados.detalle(entrega, null, atrasada: false), 'Entrega');
        expect(
          FormatoAgendados.detalle(entrega, const CobroDeAgendado(conSaldo: true), atrasada: true),
          'Entrega y pago atrasados',
        );
        expect(FormatoAgendados.detalle(entrega, null, atrasada: true), 'Entrega atrasada');
      },
    );
  });

  group('FormatoAgendados.cuando', () {
    test('la hora; la atrasada de ayer, «Ayer»; la de antes, el día', () {
      expect(FormatoAgendados.cuando(cobranza, atrasada: false, ahora: ahora), '15:00');
      expect(
        FormatoAgendados.cuando(
          itemAgenda('a', DateTime(2026, 11, 10, 18)),
          atrasada: true,
          ahora: ahora,
        ),
        'Ayer',
      );
      expect(
        FormatoAgendados.cuando(
          itemAgenda('a', DateTime(2026, 11, 7, 18)),
          atrasada: true,
          ahora: ahora,
        ),
        '07/11',
      );
      expect(
        FormatoAgendados.cuando(
          itemAgenda('a', DateTime(2025, 12, 30, 18)),
          atrasada: true,
          ahora: ahora,
        ),
        '30/12/2025',
      );
    });
  });

  group('FormatoAgendados: rótulos, chips y lugar', () {
    test('«HOY», «MAÑANA» y el día de la semana', () {
      DiaDeAgenda dia(int desdeHoy) => DiaDeAgenda(
        dia: DateTime(2026, 11, 11 + desdeHoy),
        items: const [],
        diasDesdeHoy: desdeHoy,
      );
      expect(FormatoAgendados.rotuloDelDia(dia(0)), 'HOY');
      expect(FormatoAgendados.rotuloDelDia(dia(1)), 'MAÑANA');
      expect(FormatoAgendados.rotuloDelDia(dia(2)), 'VIERNES 13');
    });

    test('los chips y sus insignias', () {
      expect(FormatoAgendados.chip(null), 'Todos');
      expect(FormatoAgendados.chip(TipoAgenda.cobranza), 'Cobranzas');
      expect(FormatoAgendados.chip(TipoAgenda.entrevista), 'Entrevistas');
      expect(FormatoAgendados.chip(TipoAgenda.entrega), 'Entregas');
      expect(FormatoAgendados.etiquetaChip(TipoAgenda.cobranza, 3), 'Cobranzas, 3');
      expect(FormatoAgendados.estadoDe(TipoAgenda.cobranza), EstadoCasa.cobranzaPendiente);
      expect(FormatoAgendados.estadoDe(TipoAgenda.entrevista), EstadoCasa.entrevistaAgendada);
      expect(FormatoAgendados.estadoDe(TipoAgenda.entrega), EstadoCasa.entregaYPago);
    });

    test('la cuenta de la pestaña: singular, plural y sin cuenta', () {
      expect(FormatoAgendados.cuentaAgendados(null), 'Agendados');
      expect(FormatoAgendados.cuentaAgendados(1), 'Agendados, 1 visita');
      expect(FormatoAgendados.cuentaAgendados(6), 'Agendados, 6 visitas');
    });

    test('el lugar: la dirección; sin dirección, la persona; sin nada, «Visita sin datos»', () {
      expect(FormatoAgendados.lugar(cobranza), 'Av. Italia 1234');
      expect(
        FormatoAgendados.lugar(itemAgenda('x', DateTime(2026, 11, 11, 15), conCasa: false)),
        'Ana Martínez',
      );
      expect(
        FormatoAgendados.lugar(
          itemAgenda('x', DateTime(2026, 11, 11, 15), conCasa: false, nombre: null, apellido: null),
        ),
        'Visita sin datos',
      );
    });

    test('la distancia une número y unidad; sin metros no hay', () {
      expect(FormatoAgendados.distancia(240), '240 m');
      expect(FormatoAgendados.distancia(null), isNull);
    });

    test('la fila se lee entera: cuándo, a dónde, qué y a cuánto', () {
      expect(
        FormatoAgendados.etiquetaDeFila(
          cobranza,
          const CobroDeAgendado(numeroCuota: 2, faltaCentavos: 145000),
          atrasada: false,
          ahora: ahora,
          metros: 40,
        ),
        '15:00. Av. Italia 1234. Cobranza · 2.ª cuota · \$U 1.450. a 40 m',
      );
    });
  });
}

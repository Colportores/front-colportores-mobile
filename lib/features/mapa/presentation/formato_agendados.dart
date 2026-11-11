import '../../agenda/domain/entities/item_agenda.dart';
import '../../agenda/domain/entities/tipo_agenda.dart';
import '../../agenda/domain/entities/vista_agenda.dart';
import '../../agenda/presentation/formato_agenda.dart';
import '../../cobranzas/domain/entities/cuota.dart';
import '../domain/entities/estado_casa.dart';
import 'formato_baja.dart';
import 'formato_hoja_casa.dart';
import 'formato_lista_ubicaciones.dart';
import 'formato_ubicaciones.dart';

/// Los textos de la hoja «Agendados» del mapa (vista 06, 06C·03). Los literales son los del canvas;
/// el vacío, el error, «Cargando» y «Limpiar filtros» son los de la pestaña Agenda (la misma lista).
abstract final class TextosAgendados {
  static const agendados = 'Agendados';

  static const todos = 'Todos';
  static const cobranzas = 'Cobranzas';
  static const entrevistas = 'Entrevistas';
  static const entregas = 'Entregas';

  static const atrasados = 'ATRASADOS';
  static const hoy = 'HOY';
  static const manana = 'MAÑANA';
  static const ayer = 'Ayer';

  static const cobranza = 'Cobranza';
  static const cobranzaAtrasada = 'Cobranza atrasada';
  static const entrevista = 'Entrevista';
  static const entrevistaAtrasada = 'Entrevista atrasada';

  /// La entrega de una venta que todavía debe: se entrega y se cobra (canvas, «Entrega y pago»).
  static const entregaYPago = 'Entrega y pago';
  static const entregaYPagoAtrasados = 'Entrega y pago atrasados';

  /// Sin nada que cobrar, lo único pendiente es entregar (como el nombre de la casa con el marcador
  /// ⇢, decisión del 10/11, P1 de #687).
  static const entregaPendiente = FormatoHojaCasa.entregaPendiente;
  static const entrega = 'Entrega';
  static const entregaAtrasada = 'Entrega atrasada';

  static const filtrarPorTipo = 'Filtrar las visitas por tipo';
}

/// Lo que la fila sabe de la venta de una visita (su plan de cuotas): la cuota y lo que falta cobrar
/// de una cobranza, y si la venta de una entrega todavía debe. `null` en cada campo = no se sabe.
final class CobroDeAgendado {
  const CobroDeAgendado({this.numeroCuota, this.faltaCentavos, this.conSaldo});

  /// La cobranza es la cuota N del plan.
  final int? numeroCuota;

  /// Lo que se espera cobrar en la visita: lo que falta de la cuota o, sin plan, el saldo de la venta.
  final int? faltaCentavos;

  /// La venta todavía debe algo (la entrega lleva un pago).
  final bool? conSaldo;

  /// Lo que dice el plan de la venta sobre la visita [item]: la cuota (si la visita es una) y lo que
  /// falta, o el saldo de la venta si es una cobranza sin plan. `null` si la visita no es de una venta.
  static CobroDeAgendado? de(ItemAgenda item, PlanDeCuotas plan) {
    final venta = plan.venta;
    switch (item.agenda.tipo) {
      case TipoAgenda.cobranza:
        for (final cuota in plan.cuotas) {
          if (cuota.agendaId == item.agenda.id) {
            return CobroDeAgendado(numeroCuota: cuota.numero, faltaCentavos: cuota.faltanCentavos);
          }
        }
        return CobroDeAgendado(faltaCentavos: venta.saldoCentavos);
      case TipoAgenda.entrega:
        return CobroDeAgendado(conSaldo: venta.tieneSaldo);
      case TipoAgenda.entrevista:
        return null;
    }
  }
}

/// Cómo se escribe cada cosa de la hoja «Agendados».
abstract final class FormatoAgendados {
  /// «Agendados, 6 visitas»: lo que lee el lector de pantalla en la pestaña.
  static String cuentaAgendados(int? total) => total == null
      ? TextosAgendados.agendados
      : '${TextosAgendados.agendados}, $total ${total == 1 ? 'visita' : 'visitas'}';

  /// El texto del chip de [tipo] (`null` = «Todos»).
  static String chip(TipoAgenda? tipo) => switch (tipo) {
    null => TextosAgendados.todos,
    TipoAgenda.cobranza => TextosAgendados.cobranzas,
    TipoAgenda.entrevista => TextosAgendados.entrevistas,
    TipoAgenda.entrega => TextosAgendados.entregas,
  };

  /// «Cobranzas, 3»: lo que lee el lector de pantalla en un chip.
  static String etiquetaChip(TipoAgenda? tipo, int cuenta) => '${chip(tipo)}, $cuenta';

  /// La insignia de la fila y del chip: el estado de la casa que pinta cada tipo de visita en el mapa
  /// (canvas: $ cobranza pendiente, ◷ entrevista agendada, ⇢ entrega y pago).
  static EstadoCasa estadoDe(TipoAgenda tipo) => switch (tipo) {
    TipoAgenda.cobranza => EstadoCasa.cobranzaPendiente,
    TipoAgenda.entrevista => EstadoCasa.entrevistaAgendada,
    TipoAgenda.entrega => EstadoCasa.entregaYPago,
  };

  /// «HOY», «MAÑANA» y, del pasado mañana en adelante, el de la Agenda («VIERNES 25»).
  static String rotuloDelDia(DiaDeAgenda dia) {
    if (dia.esHoy) return TextosAgendados.hoy;
    if (dia.esManana) return TextosAgendados.manana;
    return FormatoAgenda.rotuloDelDia(dia);
  }

  /// La columna de la izquierda: la hora («15:00») o, si está atrasada, el día: «Ayer» o «22/10».
  static String cuando(ItemAgenda item, {required bool atrasada, required DateTime ahora}) {
    final fecha = item.agenda.fechaProgramada;
    if (!atrasada) return FormatoAgenda.hora(fecha);
    final dias = FormatoListaUbicaciones.diasDeCalendario(fecha, ahora);
    return dias == 1 ? TextosAgendados.ayer : FormatoAgenda.diaMesConAnio(fecha, ahora);
  }

  /// El renglón grande: la dirección a la que hay que ir; sin dirección, con quién; sin ninguna,
  /// «Visita sin datos».
  static String lugar(ItemAgenda item) =>
      FormatoAgenda.direccion(item) ?? item.nombrePersona ?? TextosAgenda.sinDatos;

  /// El renglón chico (canvas): «Cobranza · 2.ª cuota · $U 1.450», «Cobranza atrasada · $U 980»,
  /// «Entrevista», «Entrega y pago». Lo que no se sabe (el plan todavía no se leyó, o la visita no es
  /// de una venta) no se dice: queda el tipo solo.
  static String detalle(ItemAgenda item, CobroDeAgendado? cobro, {required bool atrasada}) {
    switch (item.agenda.tipo) {
      case TipoAgenda.cobranza:
        final numero = cobro?.numeroCuota;
        final falta = cobro?.faltaCentavos;
        return [
          if (atrasada) TextosAgendados.cobranzaAtrasada else TextosAgendados.cobranza,
          if (!atrasada && numero != null) FormatoBaja.cuota(numero),
          if (falta != null && falta > 0) FormatoBaja.monto(falta),
        ].join(' · ');
      case TipoAgenda.entrevista:
        return atrasada ? TextosAgendados.entrevistaAtrasada : TextosAgendados.entrevista;
      case TipoAgenda.entrega:
        return switch (cobro?.conSaldo) {
          true => atrasada ? TextosAgendados.entregaYPagoAtrasados : TextosAgendados.entregaYPago,
          false => atrasada ? TextosAgendados.entregaAtrasada : TextosAgendados.entregaPendiente,
          null => atrasada ? TextosAgendados.entregaAtrasada : TextosAgendados.entrega,
        };
    }
  }

  /// «240 m», o `null` si no hay de dónde medir.
  static String? distancia(double? metros) {
    if (metros == null) return null;
    final texto = FormatoUbicaciones.distancia(metros);
    return texto.isEmpty ? null : texto;
  }

  /// Lo que lee el lector de pantalla de una fila: cuándo, la dirección, el detalle y la distancia.
  static String etiquetaDeFila(
    ItemAgenda item,
    CobroDeAgendado? cobro, {
    required bool atrasada,
    required DateTime ahora,
    double? metros,
  }) {
    final lejos = distancia(metros);
    return [
      cuando(item, atrasada: atrasada, ahora: ahora),
      lugar(item),
      detalle(item, cobro, atrasada: atrasada),
      if (lejos != null) 'a $lejos',
    ].join('. ');
  }
}

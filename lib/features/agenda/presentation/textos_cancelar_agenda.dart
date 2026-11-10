import '../domain/entities/tipo_agenda.dart';
import 'textos_detalle_agenda.dart';

/// Los textos de cancelar una agenda (vista 23, 23C·04 y 23C·05, HU-VIS-004). Los del canvas van tal
/// cual; los que el canvas no dibuja (marcados «a confirmar») dicen qué pasa y qué hacer.
abstract final class TextosCancelarAgenda {
  // Canvas 23C·01, 23C·04 y 23C·05.
  static const cancelarAgenda = 'Cancelar agenda';
  static const volver = 'Volver';
  static const cancelada = 'Agenda cancelada.';

  /// «¿Cancelar la entrevista?» (23C·04). Para una cobranza el canvas no la dibuja: «¿Cancelar la
  /// cobranza?» (a confirmar).
  static String titulo(TipoAgenda tipo) => switch (tipo) {
    TipoAgenda.entrevista => '¿Cancelar la entrevista?',
    TipoAgenda.cobranza => '¿Cancelar la cobranza?',
    TipoAgenda.entrega => '¿Cancelar la entrega?',
  };

  /// El cuerpo de 23C·04. La cobranza todavía no pinta la casa (su color llega con la venta, S9), así
  /// que no dice que «la casa vuelve a su estado anterior» (a confirmar: decir la verdad).
  static String cuerpo(TipoAgenda tipo) => switch (tipo) {
    TipoAgenda.entrevista =>
      'Queda como cancelada (la ves con el filtro «Canceladas»), se borra el recordatorio y la '
          'casa vuelve a su estado anterior.',
    TipoAgenda.cobranza =>
      'Queda como cancelada (la ves con el filtro «Canceladas») y se borra el recordatorio.',
    TipoAgenda.entrega =>
      'Queda como cancelada (la ves con el filtro «Canceladas») y se borra el recordatorio. Lo '
          'que falta entregar sigue pendiente.',
  };

  // A confirmar: estados que el canvas no dibuja.
  static const cancelando = 'Cancelando…';
  static const reintentar = 'Reintentar';

  /// Falla al escribir en el teléfono: el aviso de 23C·07, que el issue #455 pide para este error
  /// («la agenda sigue como estaba»); «Reintentar» dice qué hacer.
  static const noPudimosCancelar = TextosDetalleAgenda.noPudimosGuardar;

  /// La agenda se cumplió o se canceló mientras la hoja estaba abierta y la validación del
  /// repositorio no dijo más. Con un mensaje del repositorio se usa ese.
  static const yaNoSePuedeCancelar =
      'Esa agenda ya se cumplió o se canceló. Revisá la lista de agendados.';

  /// La agenda quedó cancelada pero el teléfono no pudo sacar el aviso.
  static const canceladaConRecordatorio =
      'Agenda cancelada. No pudimos borrar el recordatorio: puede sonar igual.';
}

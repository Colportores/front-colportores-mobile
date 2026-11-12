import 'color_house_status.dart';

/// El estado de una casa tal como lo resume la cache `house_status` (ADR-003, §8.4): lo que el
/// colportor ve como color y glifo en la lista y en el mapa.
///
/// «Sin visita» no es una fila de `house_status`: es la **ausencia** de fila (ADR-003), y acá es un
/// valor más para que la vista lo trate igual que los demás. El orden es el de los rótulos del
/// diseño (vista 05, «ESTADO DE LA CASA»).
///
/// [esDeVenta] separa los dos grupos del diseño: los estados de la **visita** se dibujan como
/// círculo y los de la **venta** como cuadrado (vista 06, «Círculo: estados de la visita. Cuadrado:
/// estados de la venta»).
enum EstadoCasa {
  sinVisita(esDeVenta: false),
  noContesto(esDeVenta: false),
  entrevistaAgendada(esDeVenta: false),
  entrevistaHecha(esDeVenta: false),
  ventaCompleta(esDeVenta: true),
  cobranzaPendiente(esDeVenta: true),
  entregaYPago(esDeVenta: true),
  rechazo(esDeVenta: false);

  const EstadoCasa({required this.esDeVenta});

  /// Es un estado de la venta (cuadrado) y no de la visita (círculo).
  final bool esDeVenta;

  /// El estado que dibujan la lista y el mapa para el [color] de la fila de `house_status` de una
  /// casa. Sin fila ([color] `null`) la casa es «Sin visita» (ADR-003: es la ausencia de fila).
  ///
  /// La correspondencia es 1 a 1 con los siete colores de §8.4, en el mismo orden de prioridad:
  /// 🔵 rayas = entrega y pago, 🔵 = cobranza pendiente, 🟡 = entrevista agendada, 🟢 con dorado =
  /// venta completa, 🟢 = entrevista hecha, 🔘 = no contestó, 🔴 = rechazo.
  static EstadoCasa desdeColor(ColorHouseStatus? color) => switch (color) {
    null => sinVisita,
    ColorHouseStatus.entregaYCobranzaPendiente => entregaYPago,
    ColorHouseStatus.cobranzaPendiente => cobranzaPendiente,
    ColorHouseStatus.entrevistaProgramada => entrevistaAgendada,
    ColorHouseStatus.ventaCompleta => ventaCompleta,
    ColorHouseStatus.entrevistaSinVenta => entrevistaHecha,
    ColorHouseStatus.sinContestar => noContesto,
    ColorHouseStatus.rechazo => rechazo,
  };
}

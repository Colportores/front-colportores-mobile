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
}

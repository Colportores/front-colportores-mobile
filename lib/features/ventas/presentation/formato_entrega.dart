import 'formato_venta.dart' show FormatoVenta;

/// Los textos de «Entregar ahora» (vista 27, grupo B, HU-VEN-002): los del canvas tal cual, y los que
/// el canvas no dibuja, que el agente de decisiones aceptó tal cual el 28/10 (mapa §2: texto, P2 de
/// front-colportores-mobile#159; en 27B·03 sin nada para cobrar vale «no había nada para cobrar»).
abstract final class TextosEntrega {
  // --- Del canvas (27B·01, 27B·03 y 27B·04) ---
  static const titulo = 'Entregar ahora';
  static const queEntregas = 'QUÉ ENTREGÁS';
  static const entregar = 'Entregar';
  static const tituloListo = 'Listo';
  static const ventaCompleta = 'Venta completa';
  static const volverAlMapa = 'Volver al mapa';
  static const tituloEntregaRegistrada = 'Entrega registrada';
  static const entregado = 'Entregado';
  static const todo = 'todo';
  static const saldo = 'Saldo';
  static const cobrarAhora = 'Cobrar ahora';
  static const agendarLaCobranza = 'Agendar la cobranza';
  static const casaCobranzaPendiente =
      'La casa queda como «Cobranza pendiente» hasta que el saldo llegue a cero.';

  // --- Aceptados (mapa §2: texto, 28/10) ---
  static const cargando = 'Cargando lo que vendiste';
  static const reintentar = 'Reintentar';
  static const sinProductos = 'Esta venta no tiene productos para entregar.';
  static const elegiUnProducto = 'Elegí al menos un producto para entregar.';
  static const pendiente = 'Pendiente';
  static const casaEntregaYCobranzaPendientes =
      'La casa sigue como «Entrega y cobranza pendientes» hasta que entregues lo que falta y el '
      'saldo llegue a cero.';
  static const casaEntregaPendiente =
      'Lo que falta queda pendiente para otro día. La casa se actualiza cuando lo entregues.';

  /// «Entregaste todo y está pagada…» del canvas, con la verdad cuando no había nada que cobrar.
  static String entregasteTodoYPagada({required bool habiaQueCobrar}) => habiaQueCobrar
      ? 'Entregaste todo y está pagada. La casa quedó como «Venta completa» en el mapa.'
      : 'Entregaste todo y no había nada para cobrar. La casa quedó como «Venta completa» en el '
            'mapa.';

  /// «Entregar 1 producto» (27B·02 del canvas) cuando se destildó algo; «Entregar» si va todo.
  static String entregarN(int n, {required bool todo}) =>
      todo ? entregar : 'Entregar $n ${n == 1 ? 'producto' : 'productos'}';

  /// «Nuestros Hijos queda para otro día.» (27B·02 del canvas, ahora por lo que se destilda).
  static String quedaParaOtroDia(List<String> nombres) => nombres.length == 1
      ? '${nombres.single} queda para otro día.'
      : '${_lista(nombres)} quedan para otro día.';

  /// «2 de 3 productos»: lo entregado cuando falta algo.
  static String entregadoDe(int entregados, int total) =>
      '$entregados de $total ${total == 1 ? 'producto' : 'productos'}';

  static String monto(int centavos) => FormatoVenta.monto(centavos);

  static String _lista(List<String> nombres) => nombres.length < 2
      ? nombres.join()
      : '${nombres.sublist(0, nombres.length - 1).join(', ')} y ${nombres.last}';
}

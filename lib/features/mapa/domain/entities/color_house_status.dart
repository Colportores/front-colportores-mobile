/// El color de una casa en la cache `house_status` (ADR-003, §8.4): uno de los siete estados, del
/// 1 (el que más manda) al 7. [codigo] es el valor de la columna `house_status.color`, igual en la
/// DB local y en el cloud; [prioridad] es `house_status.prioridad`, que va 1:1 con el color (el
/// servidor rechaza una fila donde no coincidan).
///
/// No es [EstadoCasa]: ese es lo que la pantalla dibuja y agrega «Sin visita», que no es una fila de
/// la cache sino su **ausencia**.
enum ColorHouseStatus {
  /// 🔵 con rayas: entrega + cobranza pendientes. Lo suma la cobranza (S9).
  entregaYCobranzaPendiente(1, 'ENTREGA_Y_COBRANZA_PENDIENTE'),

  /// 🔵: solo cobranza pendiente. Lo suma la cobranza (S9).
  cobranzaPendiente(2, 'COBRANZA_PENDIENTE'),

  /// 🟡: entrevista programada (una agenda de entrevista pendiente).
  entrevistaProgramada(3, 'ENTREVISTA_PROGRAMADA'),

  /// 🟢 con dorado: venta completa, saldo 0. Lo suma la venta (S9).
  ventaCompleta(4, 'VENTA_COMPLETA'),

  /// 🟢: entrevista dada sin venta.
  entrevistaSinVenta(5, 'ENTREVISTA_SIN_VENTA'),

  /// 🔘: nadie contestó.
  sinContestar(6, 'SIN_CONTESTAR'),

  /// 🔴: rechazo.
  rechazo(7, 'RECHAZO');

  const ColorHouseStatus(this.prioridad, this.codigo);

  /// 1 a 7; el más chico es el que se pinta cuando una casa tiene varios estados a la vez.
  final int prioridad;

  final String codigo;

  /// Inversa de [codigo]. Lanza `ArgumentError` con un valor desconocido: el `CHECK` de la tabla no
  /// lo deja entrar, así que sería un bug.
  static ColorHouseStatus desdeCodigo(String codigo) => values.firstWhere(
    (c) => c.codigo == codigo,
    orElse: () => throw ArgumentError.value(codigo, 'codigo', 'color de house_status desconocido'),
  );

  /// El de mayor prioridad (el número más chico) entre [colores], o `null` si no hay ninguno.
  static ColorHouseStatus? elDeMayorPrioridad(Iterable<ColorHouseStatus> colores) {
    ColorHouseStatus? mejor;
    for (final color in colores) {
      if (mejor == null || color.prioridad < mejor.prioridad) mejor = color;
    }
    return mejor;
  }
}

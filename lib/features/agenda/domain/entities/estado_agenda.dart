/// Estado de una agenda (`agenda.estado`, HU-VIS-002/HU-VIS-005 y backend-supabase 0068): los
/// mismos cuatro nombres en el teléfono, el servidor y el panel (decisión de Cristian del 23/10,
/// «No cumplida»). [codigo] es el valor de la columna.
///
/// - `PROGRAMADA`: la cita espera su visita. Una vencida sin resultado **sigue acá**: la app la
///   muestra en «Pendientes» hasta que se registre algo (la vencida no pasa sola a «no cumplida»).
/// - `CUMPLIDA`: la visita se hizo y la cumple.
/// - `NO_CUMPLIDA`: se registró «No contestó» sobre ella.
/// - `CANCELADA`: la colportora la canceló a mano.
enum EstadoAgenda {
  programada('PROGRAMADA'),
  cumplida('CUMPLIDA'),
  noCumplida('NO_CUMPLIDA'),
  cancelada('CANCELADA');

  const EstadoAgenda(this.codigo);

  final String codigo;

  /// Ya tuvo su desenlace (se cumplió, no se cumplió o se canceló): no se cancela ni se cumple de
  /// nuevo.
  bool get estaCerrada => this != programada;

  /// Inversa de [codigo]. Lanza `ArgumentError` con un valor desconocido (lo frena el `CHECK`).
  static EstadoAgenda desdeCodigo(String codigo) => values.firstWhere(
    (e) => e.codigo == codigo,
    orElse: () => throw ArgumentError.value(codigo, 'codigo', 'estado de agenda desconocido'),
  );
}

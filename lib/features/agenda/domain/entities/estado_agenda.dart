/// Estado de una agenda tal como lo acepta el servidor (`agenda.estado`, esquema-datos.md §Estados:
/// `PENDIENTE → COMPLETADA` al registrar la visita, `PENDIENTE → CANCELADA` a mano). [codigo] es el
/// valor de la columna.
///
/// La HU-VIS-005 habla de `PROGRAMADA`, `CUMPLIDA` y `NO_CUMPLIDA`: no coinciden con el servidor y
/// «no cumplida» no existe allá. Hasta que Cristian decida (pendiente P1 de #151), el teléfono usa
/// los tres valores del servidor y la pantalla no muestra el valor crudo.
enum EstadoAgenda {
  pendiente('PENDIENTE'),
  completada('COMPLETADA'),
  cancelada('CANCELADA');

  const EstadoAgenda(this.codigo);

  final String codigo;

  /// La visita se hizo o se canceló: ya no se puede cancelar ni cumplir de nuevo.
  bool get estaCerrada => this != pendiente;

  /// Inversa de [codigo]. Lanza `ArgumentError` con un valor desconocido (lo frena el `CHECK`).
  static EstadoAgenda desdeCodigo(String codigo) => values.firstWhere(
    (e) => e.codigo == codigo,
    orElse: () => throw ArgumentError.value(codigo, 'codigo', 'estado de agenda desconocido'),
  );
}

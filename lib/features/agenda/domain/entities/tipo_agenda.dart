/// Tipo de una agenda (esquema-datos.md §Operaciones de campo, `agenda.tipo`): para qué se
/// planificó la visita. [codigo] es el valor de la columna, en la DB local y en el cloud.
///
/// La agenda es una sola abstracción con un tipo abierto (decisión de Cristian, 23/10, «Entrega
/// día»): un tipo nuevo se suma acá y en el `CHECK` de la tabla, sin rehacerla.
enum TipoAgenda {
  entrevista('ENTREVISTA'),
  cobranza('COBRANZA'),

  /// La cita de una entrega para otro día (HU-VEN-003): lleva la venta y la entrega que la originan.
  entrega('ENTREGA');

  const TipoAgenda(this.codigo);

  final String codigo;

  /// Inversa de [codigo]. Lanza `ArgumentError` con un valor desconocido: el `CHECK` de la tabla
  /// no lo deja entrar, así que sería un bug.
  static TipoAgenda desdeCodigo(String codigo) => values.firstWhere(
    (t) => t.codigo == codigo,
    orElse: () => throw ArgumentError.value(codigo, 'codigo', 'tipo de agenda desconocido'),
  );
}

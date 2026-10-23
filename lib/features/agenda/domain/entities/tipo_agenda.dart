/// Tipo de una agenda (esquema-datos.md §Operaciones de campo, `agenda.tipo`): para qué se
/// planificó la visita. [codigo] es el valor de la columna, en la DB local y en el cloud.
enum TipoAgenda {
  entrevista('ENTREVISTA'),
  cobranza('COBRANZA');

  const TipoAgenda(this.codigo);

  final String codigo;

  /// Inversa de [codigo]. Lanza `ArgumentError` con un valor desconocido: el `CHECK` de la tabla
  /// no lo deja entrar, así que sería un bug.
  static TipoAgenda desdeCodigo(String codigo) => values.firstWhere(
    (t) => t.codigo == codigo,
    orElse: () => throw ArgumentError.value(codigo, 'codigo', 'tipo de agenda desconocido'),
  );
}

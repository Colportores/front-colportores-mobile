/// Columnas que la DB local todavía exige y el servidor dejó de tener.
///
/// **`producto.tipo`.** backend-supabase 0198 borró la columna `producto.tipo`; el pull la sigue
/// mandando, calculada con `public.tipo_de_categoria(categoria)`, mientras haya teléfonos cuya tabla
/// local la exija (`Productos.tipo` es NOT NULL en este esquema). El paso siguiente del backend es
/// sacar esa clave del pull. Si una fila de `producto` llegara sin `tipo` (o con `null`), el insert
/// fallaría por NOT NULL, se revertiría la página entera del pull y el watermark no avanzaría: el
/// teléfono dejaría de bajar el catálogo, los precios, el stock, los depósitos y los tickets.
///
/// Por eso, si falta o viene nula, se completa acá con el mismo cálculo que hace el servidor, sin
/// tocar el esquema local. La app no lee `tipo` (usa `categoria`), así que el valor solo tiene que
/// cumplir el NOT NULL; si tampoco hay una categoría conocida, queda [tipoHeredadoPorDefecto].
library;

/// El tipo que queda si la fila no trae `tipo` ni una categoría conocida.
const tipoHeredadoPorDefecto = 'LIBRO';

/// El tipo heredado de una categoría, igual que `public.tipo_de_categoria` (backend-supabase 0149).
String tipoHeredadoDeCategoria(Object? categoria) => switch (categoria) {
  'BONIFICABLES' || 'ESPIRITUALES' => 'LIBRO',
  'MISIONEROS' => 'MISIONERO',
  'REVISTAS' => 'REVISTA',
  'MATERIAL' => 'MATERIAL',
  _ => tipoHeredadoPorDefecto,
};

/// [fila] tal como llegó del cloud, con las columnas heredadas que le falten a [entidad]
/// completadas. Si no falta nada devuelve la misma fila.
Map<String, Object?> completarColumnasHeredadas(String entidad, Map<String, Object?> fila) {
  if (entidad != 'producto' || fila['tipo'] != null) return fila;
  return {...fila, 'tipo': tipoHeredadoDeCategoria(fila['categoria'])};
}

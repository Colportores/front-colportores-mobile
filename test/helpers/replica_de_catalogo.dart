// Filas del catálogo de ventas como las manda `sync.pull` (`producto`, `coleccion`,
// `producto_coleccion`), para los tests que leen la réplica local por el mismo `DriftLocalStore` del
// motor (ver `ReplicaDeCampanias.bajar`).

const _fecha = '2026-10-20T12:00:00+00:00';
const _baja = '2026-10-27T10:00:00+00:00';

/// Una fila de `producto`. [categoria] es la del servidor (`MISIONEROS`, `BONIFICABLES`…).
Map<String, Object?> filaProducto(
  String id,
  String nombre, {
  String? categoria = 'ESPIRITUALES',
  bool misionero = false,
  bool baja = false,
}) => {
  'id': id,
  'nombre': nombre,
  'descripcion': null,
  'tipo': 'LIBRO',
  'categoria': categoria,
  'es_bonificable': false,
  'es_misionero': misionero,
  'precio_base_compra': null,
  'casa_editora': null,
  'imagen_url': null,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': baja ? _baja : null,
  'sync_version': 1,
  'codigo_editor': null,
};

/// Una fila de `coleccion` (un combo).
Map<String, Object?> filaCombo(String id, String nombre, {int aElegir = 0, bool baja = false}) => {
  'id': id,
  'nombre': nombre,
  'libros_a_elegir': aElegir,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': baja ? _baja : null,
  'sync_version': 1,
};

/// Una fila de `producto_coleccion`: [productoId] va siempre en el combo [comboId].
Map<String, Object?> filaComponente(
  String id,
  String productoId,
  String comboId, {
  int cantidad = 1,
  bool baja = false,
}) => {
  'id': id,
  'producto_id': productoId,
  'coleccion_id': comboId,
  'cantidad': cantidad,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': baja ? _baja : null,
  'sync_version': 1,
};

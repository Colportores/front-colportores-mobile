import 'dart:convert';

import 'package:drift/drift.dart';

/// Lo que vuelve en una devolución (`devolucion.productos_devueltos`, un `jsonb` del cloud) guardado
/// como texto JSON en SQLite: `[{"producto_id": "<uuid>", "cantidad": 1, "venta_item_id": "<uuid>"}, …]`.
final class ProductosDevueltosConverter extends TypeConverter<List<Object?>, String> {
  const ProductosDevueltosConverter();

  @override
  List<Object?> fromSql(String fromDb) => jsonDecode(fromDb) as List<Object?>;

  @override
  String toSql(List<Object?> value) => jsonEncode(value);
}

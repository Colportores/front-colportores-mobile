import 'dart:convert';

import 'package:drift/drift.dart';

/// Lo que traía un combo al venderse (`venta_item.componentes`, un `jsonb` del cloud) guardado como
/// texto JSON en SQLite: `[{"producto_id": "<uuid>", "cantidad": 2}, …]`.
final class ComponentesConverter extends TypeConverter<List<Object?>, String> {
  const ComponentesConverter();

  @override
  List<Object?> fromSql(String fromDb) => jsonDecode(fromDb) as List<Object?>;

  @override
  String toSql(List<Object?> value) => jsonEncode(value);
}

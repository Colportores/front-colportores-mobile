import 'dart:convert';

import 'package:drift/drift.dart';

/// Un objeto GeoJSON (el `jsonb` del cloud) guardado como texto JSON en SQLite.
final class GeojsonConverter extends TypeConverter<Map<String, Object?>, String> {
  const GeojsonConverter();

  @override
  Map<String, Object?> fromSql(String fromDb) => jsonDecode(fromDb) as Map<String, Object?>;

  @override
  String toSql(Map<String, Object?> value) => jsonEncode(value);
}

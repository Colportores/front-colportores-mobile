import 'dart:convert';

import 'package:drift/drift.dart';

/// Un objeto JSON (un `jsonb` del cloud) guardado como texto JSON en SQLite.
///
/// El pull lo recibe como `Map` y la app lo lee y lo escribe como `Map<String, Object?>`; en la tabla vive
/// como texto (`jsonEncode`).
final class ObjetoJsonConverter extends TypeConverter<Map<String, Object?>, String> {
  const ObjetoJsonConverter();

  @override
  Map<String, Object?> fromSql(String fromDb) =>
      Map<String, Object?>.from(jsonDecode(fromDb) as Map<Object?, Object?>);

  @override
  String toSql(Map<String, Object?> value) => jsonEncode(value);
}

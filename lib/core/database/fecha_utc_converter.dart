import 'package:drift/drift.dart';

/// `DateTime` ↔ epoch en **milisegundos** (`INTEGER`), siempre en UTC.
///
/// Es el formato de fecha de toda tabla local: 08-conceptos-transversales.md §8.11 fija
/// "epoch en milisegundos (`int`) en DB; `DateTime` en dominio". Las columnas `dateTime()` de
/// Drift no sirven para eso: por defecto guardan epoch en **segundos** (se pierden los
/// milisegundos) y al leer devuelven hora local, así que la misma fila leída de la DB y del cloud
/// daría distinta (ver el invariante de fechas en `Auditoria`). Se declara así:
///
/// ```dart
/// IntColumn get inicio => integer().map(const FechaUtcConverter())();
/// IntColumn get fin => integer().nullable().map(const FechaUtcConverter())();
/// ```
///
/// Lo que haya por debajo del milisegundo se descarta al guardar. Como el valor es un entero, las
/// comparaciones en SQL (`fin >= inicio`, `ORDER BY inicio`) son exactas.
final class FechaUtcConverter extends TypeConverter<DateTime, int> {
  const FechaUtcConverter();

  @override
  DateTime fromSql(int fromDb) => DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}

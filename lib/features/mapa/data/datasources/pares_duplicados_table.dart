import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `ubicacion_par_decidido` de la DB local cifrada: lo que el colportor decidió sobre un par
/// de posibles duplicados del scan ("Conservar ambos" o "Ignorar", HU-UBI-006), para que el par no
/// vuelva a aparecer durante 30 días.
///
/// **Solo local**: no tiene tabla en el cloud ni entra al sync (es una preferencia de revisión del
/// colportor, no un dato de negocio). Una fila por par, con los dos `id` ordenados
/// ([ubicacionAId] < [ubicacionBId], `ParDuplicado.clave`); decidir de nuevo pisa la decisión y la
/// fecha. Las filas vencidas no se borran: el scan las ignora por fecha.
@DataClassName('ParDecididoFila')
class ParesDecididos extends Table {
  @override
  String get tableName => 'ubicacion_par_decidido';

  TextColumn get ubicacionAId => text()();

  TextColumn get ubicacionBId => text()();

  /// `CONSERVAR_AMBOS` o `IGNORAR`.
  TextColumn get decision => text()();

  IntColumn get decididoEn => integer().map(const FechaUtcConverter())();

  @override
  Set<Column<Object>> get primaryKey => {ubicacionAId, ubicacionBId};

  @override
  List<String> get customConstraints => const [
    "CHECK (decision IN ('CONSERVAR_AMBOS', 'IGNORAR'))",
    'CHECK (ubicacion_a_id < ubicacion_b_id)',
  ];
}

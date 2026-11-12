import 'package:drift/drift.dart';

/// `sync_fuera_del_area`: las filas que el motor marcó «fuera del área» (contrato-sync-engine §2.1).
/// **Nada se borra por esto**: la fila sigue en su tabla, y la app decide si la muestra (R-UB12, solo
/// visual).
///
/// Es una tabla del motor, como `sync_queue` y `sync_watermark`: no es una entidad del contrato, no
/// se declara en `catalogo.dart` y no sube.
///
/// [confirmada] separa lo que ya se sabe que quedó afuera de lo que está a la espera de volver a
/// bajar después de un `area_reset`: hasta la última página de esa descarga, una casa que todavía no
/// bajó no está afuera. La app lee solo las confirmadas. Una fila que vuelve a bajar se borra de acá.
@DataClassName('FueraDelAreaFila')
class SyncFueraDelArea extends Table {
  @override
  String get tableName => 'sync_fuera_del_area';

  /// La entidad del contrato (`ubicacion`, `espacio`, `house_status`).
  TextColumn get entidad => text()();

  /// La PK de la fila en su tabla (`id`, o `ubicacion_id` en `house_status`).
  TextColumn get filaId => text()();

  BoolColumn get confirmada => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {entidad, filaId};
}

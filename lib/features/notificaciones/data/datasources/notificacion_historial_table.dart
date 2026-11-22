import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `notificacion_historial` de la DB local cifrada (HU-NOT-005, centro de notificaciones).
///
/// **local-only**: no tiene tabla en el cloud y no entra al sync (`SyncSpec.local`); solo viaja en el
/// backup E2E. Una fila por aviso recibido: [titulo] y [detalle] son el texto que se le mostró a la
/// persona (la dirección y el tipo, nunca el nombre del cliente, R-NO02) y [destino] el enlace
/// interno al que lleva tocarlo (`agenda/<uuid>`). No hay baja lógica: «Borrar todas» y la purga de
/// los 90 días borran la fila (la HU pide que la tabla quede vacía).
///
/// El [id] lo pone quien registra el aviso: es lo que hace idempotente el registro (el mismo aviso,
/// dos veces, es una fila). [leidaEn] `NULL` = sin leer.
@DataClassName('NotificacionFila')
@TableIndex(name: 'notificacion_historial_recibida_idx', columns: {#recibidaEn})
class NotificacionesHistorial extends Table {
  @override
  String get tableName => 'notificacion_historial';

  TextColumn get id => text()();

  /// `TipoNotificacion.codigo`.
  TextColumn get tipo => text()();

  TextColumn get titulo => text()();

  TextColumn get detalle => text().nullable()();

  /// `DestinoNotificacion.enlace`, o `NULL` si el aviso no lleva a ningún lado.
  TextColumn get destino => text().nullable()();

  IntColumn get recibidaEn => integer().map(const FechaUtcConverter())();

  IntColumn get leidaEn => integer().nullable().map(const FechaUtcConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

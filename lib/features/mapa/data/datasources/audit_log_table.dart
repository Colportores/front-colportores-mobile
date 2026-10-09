import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Eventos del `audit_log` local. Hoy la baja de una ubicación (HU-UBI-005); «marcar como duplicado»
/// (`duplicado_de_A`, HU-UBI-006) y la justificación de «Crear igual» (HU-UBI-001, #282) escriben acá
/// con su propio evento.
abstract final class EventoAuditoriaLocal {
  /// La baja de una ubicación, con el motivo que eligió el colportor.
  static const ubicacionBaja = 'ubicacion_baja';
}

/// Tabla `audit_log` de la DB local cifrada: la auditoría del dispositivo (R-UB09; las HU la llaman
/// `audit_log_local` para distinguirla del `audit_log` cloud de HU-ADM-007).
///
/// **Solo local**: no tiene tabla en el cloud ni entra al sync, y no se borra con las ubicaciones.
/// [motivo] puede ser texto libre del colportor, así que **nunca** va a los logs ni a la telemetría
/// (esquema-datos, «`audit_log` local»). Una fila por evento: [evento] dice qué pasó, [uuid] a qué fila
/// ([Ubicaciones.id], por ejemplo) y [creadoEn] cuándo, con la misma marca que la columna de la fila
/// afectada (la de la baja es `ubicacion.deleted_at`): así la Lista encuentra el motivo de la baja
/// vigente sin confundirlo con el de una baja anterior ya reactivada.
@DataClassName('AuditLogFila')
@TableIndex(name: 'audit_log_evento_uuid_idx', columns: {#evento, #uuid})
class AuditLogLocal extends Table {
  @override
  String get tableName => 'audit_log';

  IntColumn get id => integer().autoIncrement()();

  /// Qué pasó: ver [EventoAuditoriaLocal].
  TextColumn get evento => text()();

  /// El `id` de la fila afectada.
  TextColumn get uuid => text()();

  /// El motivo, si el evento lo tiene. Texto del colportor: no sale de la DB hacia logs ni telemetría.
  TextColumn get motivo => text().nullable()();

  IntColumn get creadoEn => integer().map(const FechaUtcConverter())();
}

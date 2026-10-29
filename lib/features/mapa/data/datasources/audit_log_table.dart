import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Eventos del `audit_log` local. Hoy la baja de una ubicación (HU-UBI-005); «marcar como duplicado»
/// (`duplicado_de_A`, HU-UBI-006) y la justificación de «Crear igual» (HU-UBI-001, #282) escriben acá
/// con su propio evento.
abstract final class EventoAuditoriaLocal {
  /// La baja de una ubicación, con el motivo que eligió el colportor.
  static const ubicacionBaja = 'ubicacion_baja';

  /// La justificación de «Crear igual» (HU-UBI-001, #282): `uuid` es el `id` de la ubicación nueva
  /// (o la que se está editando y se deja igual, HU-UBI-004), `motivo` lo que escribió el colportor y
  /// `creado_en` el `updated_at` con que quedó guardada. Solo local: no se sincroniza.
  static const ubicacionCrearIgual = 'ubicacion_crear_igual';

  /// La baja de una persona (HU-UBI-011), con su motivo si lo hay. `uuid` es el `id` de la persona y
  /// `creado_en` el mismo instante que su `deleted_at`.
  static const personaBaja = 'persona_baja';

  /// El toque en «Llamar» de la ficha de una persona (HU-UBI-009, `click_to_call`). `uuid` es el `id`
  /// de la persona; **nunca** el número ni nada de sus datos. Sin motivo. Solo local.
  static const clickToCall = 'click_to_call';

  /// Una agenda modificada (HU-VIS-003, «Audit log local»): `uuid` es el `id` de la agenda y
  /// `creado_en` el instante del cambio. Sin motivo: la nota y la hora son datos de la persona y no
  /// se copian acá.
  static const agendaModificada = 'agenda_modificada';

  /// Una venta con el total cambiado a mano (HU-VEN-001, S38): `uuid` es el `id` de la venta,
  /// `creado_en` el instante de la venta y `motivo` la diferencia (`diferencia_centavos:-40000`, el
  /// cobrado menos el calculado). El texto que escribió la colportora no se copia acá: viaja con la
  /// venta (`motivo_monto_manual`).
  static const ventaMontoManual = 'venta_monto_manual';

  /// La verificación semanal del backup en Drive encontró la cadena entera (HU-SYNC-009). `uuid` es
  /// [uuidBackup] y `creado_en` el instante de la verificación. Sin motivo.
  static const backupIntegridadOk = 'backup_integrity_ok';

  /// La verificación encontró un problema y se regenera la base (HU-SYNC-009). `motivo` son los
  /// problemas por nombre (`corrupt`, `brokenLink`…), nunca contenido del backup.
  static const backupIntegridadProblema = 'backup_integrity_problem';

  /// El `uuid` de los eventos del backup: no hay una fila afectada, es el backup en su conjunto.
  static const uuidBackup = 'backup';
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

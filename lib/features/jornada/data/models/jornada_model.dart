import '../../../../core/domain/entities/auditoria.dart';
import '../../domain/entities/jornada.dart';

/// DTO de [Jornada]: la entidad más (de)serialización. Es lo único que cruza hacia los data
/// sources.
///
/// [toJson] usa los nombres de columna del esquema físico de la tabla `jornada`
/// (`backend-supabase`, migración 0001; `acompaniante_id` / `tipo_acompaniamiento`, sin `ñ`) y
/// las fechas en ISO-8601 UTC, así que sirve de payload para encolar el sync cuando entre el
/// motor (contrato-sync-engine.md §3, `engine.stage(Tables.jornada, …)`). `jornada` no tiene
/// columnas con PII, y el test del modelo fija la lista exacta de claves para que no se cuele
/// ninguna.
///
/// Ojo con Equatable: compara también el `runtimeType`, así que un `JornadaModel` **no es igual**
/// a una `Jornada` con los mismos datos. Los repositorios devuelven al dominio [toEntity], nunca
/// el modelo.
final class JornadaModel extends Jornada {
  JornadaModel({
    required super.id,
    required super.colportorId,
    required super.inicio,
    super.fin,
    super.acompananteId,
    super.tipoAcompanamiento,
    super.totalVisitas,
    super.totalVentas,
    required super.auditoria,
  });

  factory JornadaModel.fromEntity(Jornada jornada) => JornadaModel(
    id: jornada.id,
    colportorId: jornada.colportorId,
    inicio: jornada.inicio,
    fin: jornada.fin,
    acompananteId: jornada.acompananteId,
    tipoAcompanamiento: jornada.tipoAcompanamiento,
    totalVisitas: jornada.totalVisitas,
    totalVentas: jornada.totalVentas,
    auditoria: jornada.auditoria,
  );

  factory JornadaModel.fromJson(Map<String, Object?> json) => JornadaModel(
    id: json['id']! as String,
    colportorId: json['colportor_id']! as String,
    inicio: _fecha(json['inicio'])!,
    fin: _fecha(json['fin']),
    acompananteId: json['acompaniante_id'] as String?,
    tipoAcompanamiento: json['tipo_acompaniamiento'] as String?,
    totalVisitas: json['total_visitas']! as int,
    totalVentas: json['total_ventas']! as int,
    auditoria: Auditoria(
      createdAt: _fecha(json['created_at'])!,
      updatedAt: _fecha(json['updated_at'])!,
      createdBy: json['created_by'] as String?,
      deletedAt: _fecha(json['deleted_at']),
      syncVersion: json['sync_version']! as int,
    ),
  );

  Jornada toEntity() => Jornada(
    id: id,
    colportorId: colportorId,
    inicio: inicio,
    fin: fin,
    acompananteId: acompananteId,
    tipoAcompanamiento: tipoAcompanamiento,
    totalVisitas: totalVisitas,
    totalVentas: totalVentas,
    auditoria: auditoria,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'colportor_id': colportorId,
    'inicio': inicio.toUtc().toIso8601String(),
    'fin': fin?.toUtc().toIso8601String(),
    'acompaniante_id': acompananteId,
    'tipo_acompaniamiento': tipoAcompanamiento,
    'total_visitas': totalVisitas,
    'total_ventas': totalVentas,
    'created_at': auditoria.createdAt.toUtc().toIso8601String(),
    'updated_at': auditoria.updatedAt.toUtc().toIso8601String(),
    'created_by': auditoria.createdBy,
    'deleted_at': auditoria.deletedAt?.toUtc().toIso8601String(),
    'sync_version': auditoria.syncVersion,
  };

  /// `timestamptz` llega con zona (`…Z` o `…+00:00`); se normaliza a UTC igual que la entidad.
  static DateTime? _fecha(Object? valor) =>
      valor == null ? null : DateTime.parse(valor as String).toUtc();
}

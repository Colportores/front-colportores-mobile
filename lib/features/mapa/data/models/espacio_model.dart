import '../../../../core/domain/entities/auditoria.dart';
import '../../domain/entities/espacio.dart';

/// DTO de [Espacio]. [toJson] usa los nombres de columna de `public.espacio` (`backend-supabase`,
/// migración 0001 menos la `descripcion` que saca la 0104) y es el payload del sync: del depto solo
/// suben `numero_depto` y `piso` (ADR-004; HU-UBI-007, «Nota por depto»). Ningún texto libre sale
/// del teléfono: la `descripcion` que traía la tabla local ya no se lee, ni se escribe, ni se
/// manda. Ver `UbicacionModel` para el resto de las reglas.
final class EspacioModel extends Espacio {
  const EspacioModel({
    required super.id,
    required super.ubicacionId,
    super.numeroDepto,
    super.piso,
    required super.auditoria,
  });

  factory EspacioModel.fromEntity(Espacio espacio) => EspacioModel(
    id: espacio.id,
    ubicacionId: espacio.ubicacionId,
    numeroDepto: espacio.numeroDepto,
    piso: espacio.piso,
    auditoria: espacio.auditoria,
  );

  factory EspacioModel.fromJson(Map<String, Object?> json) => EspacioModel(
    id: json['id']! as String,
    ubicacionId: json['ubicacion_id']! as String,
    numeroDepto: json['numero_depto'] as String?,
    piso: json['piso'] as String?,
    auditoria: Auditoria(
      createdAt: DateTime.parse(json['created_at']! as String),
      updatedAt: DateTime.parse(json['updated_at']! as String),
      createdBy: json['created_by'] as String?,
      deletedAt: json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at']! as String),
      syncVersion: json['sync_version']! as int,
    ),
  );

  Espacio toEntity() => Espacio(
    id: id,
    ubicacionId: ubicacionId,
    numeroDepto: numeroDepto,
    piso: piso,
    auditoria: auditoria,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'ubicacion_id': ubicacionId,
    'numero_depto': numeroDepto,
    'piso': piso,
    'created_at': auditoria.createdAt.toIso8601String(),
    'updated_at': auditoria.updatedAt.toIso8601String(),
    'created_by': auditoria.createdBy,
    'deleted_at': auditoria.deletedAt?.toIso8601String(),
    'sync_version': auditoria.syncVersion,
  };
}

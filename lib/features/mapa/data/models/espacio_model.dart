import '../../../../core/domain/entities/auditoria.dart';
import '../../domain/entities/espacio.dart';

/// DTO de [Espacio]. [toJson] usa los nombres de columna de `public.espacio` (`backend-supabase`,
/// migración 0001) y es el payload del sync: `numero_depto` y `piso` van al cloud siempre
/// (ADR-004). Ver `UbicacionModel` para el resto de las reglas.
final class EspacioModel extends Espacio {
  const EspacioModel({
    required super.id,
    required super.ubicacionId,
    super.numeroDepto,
    super.piso,
    super.descripcion,
    required super.auditoria,
  });

  factory EspacioModel.fromEntity(Espacio espacio) => EspacioModel(
    id: espacio.id,
    ubicacionId: espacio.ubicacionId,
    numeroDepto: espacio.numeroDepto,
    piso: espacio.piso,
    descripcion: espacio.descripcion,
    auditoria: espacio.auditoria,
  );

  factory EspacioModel.fromJson(Map<String, Object?> json) => EspacioModel(
    id: json['id']! as String,
    ubicacionId: json['ubicacion_id']! as String,
    numeroDepto: json['numero_depto'] as String?,
    piso: json['piso'] as String?,
    descripcion: json['descripcion'] as String?,
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
    descripcion: descripcion,
    auditoria: auditoria,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'ubicacion_id': ubicacionId,
    'numero_depto': numeroDepto,
    'piso': piso,
    'descripcion': descripcion,
    'created_at': auditoria.createdAt.toIso8601String(),
    'updated_at': auditoria.updatedAt.toIso8601String(),
    'created_by': auditoria.createdBy,
    'deleted_at': auditoria.deletedAt?.toIso8601String(),
    'sync_version': auditoria.syncVersion,
  };
}

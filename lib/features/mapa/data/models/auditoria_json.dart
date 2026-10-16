import '../../../../core/domain/entities/auditoria.dart';

/// Las columnas de auditoría de una fila del cloud (`created_at`, `updated_at`, `created_by`,
/// `deleted_at`, `sync_version`), como llegan en el delta del sync: `timestamptz` en ISO-8601 con
/// zona (`…Z` o `…+00:00`), que [Auditoria] normaliza a UTC.
Auditoria auditoriaDesdeJson(Map<String, Object?> json) => Auditoria(
  createdAt: DateTime.parse(json['created_at']! as String),
  updatedAt: DateTime.parse(json['updated_at']! as String),
  createdBy: json['created_by'] as String?,
  deletedAt: switch (json['deleted_at']) {
    final String fecha => DateTime.parse(fecha),
    _ => null,
  },
  syncVersion: (json['sync_version']! as num).toInt(),
);

/// Inversa de [auditoriaDesdeJson], con las fechas en ISO-8601 UTC.
Map<String, Object?> auditoriaAJson(Auditoria auditoria) => {
  'created_at': auditoria.createdAt.toIso8601String(),
  'updated_at': auditoria.updatedAt.toIso8601String(),
  'created_by': auditoria.createdBy,
  'deleted_at': auditoria.deletedAt?.toIso8601String(),
  'sync_version': auditoria.syncVersion,
};

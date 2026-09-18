import 'package:equatable/equatable.dart';

/// Metadata de auditoría común a toda entidad persistida
/// (esquema-datos.md §Principios 3 y 5: `created_at`, `updated_at`, `created_by`,
/// `deleted_at`, `sync_version`).
///
/// Value object de dominio: Dart puro, sin imports de Flutter/Drift/Supabase (ADR-009).
class Auditoria extends Equatable {
  const Auditoria({
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.deletedAt,
    this.syncVersion = 0,
  });

  final DateTime createdAt;
  final DateTime updatedAt;

  /// UUID v7 del usuario que creó el registro. Nullable: el esquema no aclara si toda fila
  /// tiene un creador conocido desde el origen (ej. datos semilla).
  final String? createdBy;

  /// Soft delete (esquema-datos.md §Principios 6): nunca se borra físicamente, se marca acá.
  final DateTime? deletedAt;

  /// Incremental; lo asigna el backend tras aceptar el cambio (esquema-datos.md §Principios 5).
  final int syncVersion;

  /// `true` si el registro fue borrado lógicamente.
  bool get estaBorrada => deletedAt != null;

  @override
  List<Object?> get props => [createdAt, updatedAt, createdBy, deletedAt, syncVersion];
}

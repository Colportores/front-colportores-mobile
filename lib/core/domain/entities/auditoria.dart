import 'package:equatable/equatable.dart';

/// Centinela de [Auditoria.copyWith]: distingue "no se pasó el argumento" de "se pasó `null`".
const Object _sinCambio = Object();

/// Metadata de auditoría común a toda entidad persistida
/// (esquema-datos.md §Principios 3 y 5: `created_at`, `updated_at`, `created_by`,
/// `deleted_at`, `sync_version`).
///
/// Value object de dominio: Dart puro, sin imports de Flutter/Drift/Supabase (ADR-009).
///
/// **Invariante: toda fecha se guarda en UTC.** `DateTime.==` compara también el flag `isUtc`,
/// pero `hashCode` no: la misma fila hidratada desde la DB local (`isUtc: false`) y desde el
/// cloud (`DateTime.parse('…Z')`, `isUtc: true`) daría desigual con el mismo `hashCode` — rompe
/// `Set`/`Map` y le muestra al sync engine un cambio fantasma en cada pull. El constructor
/// normaliza con `toUtc()`, así que el invariante no depende de que cada llamador se acuerde.
class Auditoria extends Equatable {
  Auditoria({
    required DateTime createdAt,
    required DateTime updatedAt,
    this.createdBy,
    DateTime? deletedAt,
    this.syncVersion = 0,
  }) : createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       deletedAt = deletedAt?.toUtc();

  /// Siempre en UTC — ver el invariante en el doc de la clase.
  final DateTime createdAt;

  /// Siempre en UTC — ver el invariante en el doc de la clase.
  final DateTime updatedAt;

  /// UUID v7 del usuario que creó el registro. Nullable: el esquema no aclara si toda fila
  /// tiene un creador conocido desde el origen (ej. datos semilla).
  ///
  /// TODO(#8): §Principios 3 lo lista como campo de auditoría universal, así que hacerlo
  /// nullable es apartarse del esquema — decisión pendiente (ver comentario en el issue #8).
  final String? createdBy;

  /// Soft delete (esquema-datos.md §Principios 6): nunca se borra físicamente, se marca acá.
  /// Siempre en UTC — ver el invariante en el doc de la clase.
  final DateTime? deletedAt;

  /// Incremental; lo asigna el backend tras aceptar el cambio (esquema-datos.md §Principios 5).
  final int syncVersion;

  /// `true` si el registro fue borrado lógicamente.
  bool get estaBorrada => deletedAt != null;

  /// Copia con los campos indicados reemplazados.
  ///
  /// El sync engine actualiza `sync_version` fila por fila al aceptar un push; sin esto habría
  /// que reconstruir la entidad campo por campo y un campo olvidado revertiría datos reales.
  /// [createdBy] y [deletedAt] aceptan `null` explícito (revertir un soft delete, por ejemplo):
  /// omitir el argumento conserva el valor actual, pasar `null` lo borra.
  Auditoria copyWith({
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? createdBy = _sinCambio,
    Object? deletedAt = _sinCambio,
    int? syncVersion,
  }) => Auditoria(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdBy: identical(createdBy, _sinCambio) ? this.createdBy : createdBy as String?,
    deletedAt: identical(deletedAt, _sinCambio) ? this.deletedAt : deletedAt as DateTime?,
    syncVersion: syncVersion ?? this.syncVersion,
  );

  @override
  List<Object?> get props => [createdAt, updatedAt, createdBy, deletedAt, syncVersion];
}

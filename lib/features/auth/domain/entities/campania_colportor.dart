import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Asociación usuario ↔ campaña con zona asignada
/// (esquema-datos.md §Identidad, tabla `campania_colportor`).
class CampaniaColportor extends Equatable {
  const CampaniaColportor({
    required this.id,
    required this.campaniaId,
    required this.usuarioId,
    required this.zonaId,
    required this.metaLibros,
    required this.auditoria,
  });

  final String id;

  /// FK a `campania.id`.
  final String campaniaId;

  /// FK a `usuario.id`.
  final String usuarioId;

  /// FK a `zona.id` (entidad de Geografía, fuera del alcance de #8 — se referencia por id).
  final String zonaId;

  /// Snapshot de la beca a la carrera del colportor al momento de la asignación
  /// (esquema-datos.md: "meta_libros (snapshot de la beca a su carrera...)").
  final int metaLibros;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [id, campaniaId, usuarioId, zonaId, metaLibros, auditoria];
}

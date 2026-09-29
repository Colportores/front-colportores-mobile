import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Inscripción de un usuario en una campaña, con la zona que tiene asignada, si tiene una
/// (esquema-datos.md §Identidad, tabla `campania_colportor`).
class CampaniaColportor extends Equatable {
  const CampaniaColportor({
    required this.id,
    required this.campaniaId,
    required this.usuarioId,
    this.zonaId,
    required this.metaLibros,
    required this.auditoria,
  });

  final String id;

  /// FK a `campania.id`.
  final String campaniaId;

  /// FK a `usuario.id`.
  final String usuarioId;

  /// FK a `zona.id`, o `null`: el colportor está inscripto pero «sin zona» (cambio de modelo del
  /// 29/09, backend-supabase 0009). Es el **único** lugar donde se guarda la zona de un colportor, y
  /// es de una ciudad de la misma campaña. Las casas que registra no dependen de esto: su zona sale
  /// de la posición (`ZonaPorPosicion`, #231).
  final String? zonaId;

  /// Snapshot de la beca a la carrera del colportor al momento de la asignación
  /// (esquema-datos.md: "meta_libros (snapshot de la beca a su carrera...)").
  final int metaLibros;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [id, campaniaId, usuarioId, zonaId, metaLibros, auditoria];
}

import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Una nota de una persona (esquema-datos.md §`nota`, `target_type = PERSONA`; HU-UBI-012).
///
/// **local-only — PII**: el texto es lo más sensible del módulo (puede hablar de deudas o de la
/// familia) y nunca sale del teléfono ni va a los logs.
class NotaPersona extends Equatable {
  const NotaPersona({
    required this.id,
    required this.personaId,
    required this.texto,
    required this.auditoria,
  });

  final String id;

  /// FK a `persona.id` (`nota.target_id`).
  final String personaId;

  final String texto;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  /// Apagado por la misma razón que `Persona.stringify`: `'$nota'` o un log con la nota imprimiría el
  /// texto (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [id, personaId, texto, auditoria];
}

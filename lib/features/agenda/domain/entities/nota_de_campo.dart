import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// La nota opcional de una agenda o de una visita (esquema-datos.md §`nota`, `target_type = AGENDA`
/// o `VISITA`): el objeto al que se ata lo decide la operación que la recibe.
///
/// **local-only — PII**: el texto nunca sale del teléfono ni va a los logs. Se guarda en la misma
/// transacción local que la agenda o la visita (ADR-017).
class NotaDeCampo extends Equatable {
  const NotaDeCampo({required this.id, required this.texto, required this.auditoria});

  final String id;

  final String texto;

  final Auditoria auditoria;

  /// Apagado por la misma razón que `NotaPersona.stringify`: `'$nota'` o un log con la nota
  /// imprimiría el texto (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [id, texto, auditoria];
}

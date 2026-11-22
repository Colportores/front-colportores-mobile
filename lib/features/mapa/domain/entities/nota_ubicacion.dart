import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import 'nota_de_texto.dart';

/// Una nota de un lugar (esquema-datos.md §`nota`, `target_type = UBICACION`; vista 39, C·05). Un
/// lugar tiene todas las que quiera, cada una con su fecha (decisión de Cristian, 23/10, «Notas
/// casa»).
///
/// **local-only — PII**: el texto lo escribe la colportora y nunca sale del teléfono ni va a los logs.
class NotaUbicacion extends Equatable implements NotaDeTexto {
  const NotaUbicacion({
    required this.id,
    required this.ubicacionId,
    required this.texto,
    required this.auditoria,
  });

  @override
  final String id;

  /// FK a `ubicacion.id` (`nota.target_id`).
  final String ubicacionId;

  @override
  final String texto;

  @override
  final Auditoria auditoria;

  @override
  bool get estaBorrada => auditoria.estaBorrada;

  /// Apagado por la misma razón que `NotaPersona.stringify`: `'$nota'` o un log con la nota
  /// imprimiría el texto (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [id, ubicacionId, texto, auditoria];
}

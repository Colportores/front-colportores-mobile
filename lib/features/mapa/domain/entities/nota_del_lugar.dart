import 'package:equatable/equatable.dart';

/// Una nota de un lugar (esquema-datos.md §`nota`, `target_type = UBICACION`; vista 39, «NOTA DEL
/// LUGAR» de C·01 y C·05).
///
/// **local-only — PII**: el texto lo escribe la colportora y nunca sale del teléfono ni va a los logs.
class NotaDelLugar extends Equatable {
  const NotaDelLugar({required this.id, required this.texto, required this.creadaEl});

  final String id;
  final String texto;
  final DateTime creadaEl;

  /// Apagado por la misma razón que `NotaPersona.stringify`: un `'$nota'` o un log con la nota
  /// imprimiría el texto (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [id, texto, creadaEl];
}

import 'package:equatable/equatable.dart';

/// Una entrevista que el colportor ya tiene agendada cerca de la casa que está por agendar
/// (vista 39, R·02): solo lo que hace falta para sugerir una fecha. No lleva persona ni dirección.
class EntrevistaCercana extends Equatable {
  const EntrevistaCercana({required this.fecha, this.slotCodigo});

  /// Cuándo es (`agenda.fecha_programada`).
  final DateTime fecha;

  /// La franja que se le recomendó al agendarla (`agenda.slot_codigo`), si la tiene.
  final String? slotCodigo;

  @override
  List<Object?> get props => [fecha, slotCodigo];
}

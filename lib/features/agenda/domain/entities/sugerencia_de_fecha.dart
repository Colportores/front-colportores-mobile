import 'package:equatable/equatable.dart';

import 'franja_horaria.dart';

/// La fecha que se le sugiere a quien agenda una entrevista porque ese día ya tiene otras cerca (vista
/// 39, R·02: «2 entrevistas a menos de 300 m ese día»).
class SugerenciaDeFecha extends Equatable {
  const SugerenciaDeFecha({required this.momento, required this.cantidad, this.franja});

  /// El día y la hora con que queda el formulario al aceptarla (hora local): el comienzo de [franja],
  /// o, si ninguna de las entrevistas de ese día cae en una franja, la hora de la más temprana.
  final DateTime momento;

  /// Cuántas entrevistas hay a menos de 300 m ese día.
  final int cantidad;

  /// La franja que más se repite ese día; `null` si ninguna entrevista de ese día cae en una franja.
  final FranjaHoraria? franja;

  @override
  List<Object?> get props => [momento, cantidad, franja];
}

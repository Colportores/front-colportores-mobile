import 'package:equatable/equatable.dart';

import '../../../agenda/domain/entities/visita.dart';

/// La última visita de un espacio (un depto, una casa, un negocio): lo que muestra el encabezado de la
/// ficha del depto, «✓ Entrevista hecha · 20/09» (vista 11·04). Solo lo que hace falta para decirlo:
/// el resultado y el día. No lleva persona, nota ni jornada.
class UltimaVisitaDelEspacio extends Equatable {
  UltimaVisitaDelEspacio({required this.resultado, required DateTime fecha})
    : fecha = fecha.toUtc();

  final TipoResultadoVisita resultado;

  /// Cuándo fue la visita (UTC); la vista la escribe en hora local.
  final DateTime fecha;

  @override
  List<Object?> get props => [resultado, fecha];
}

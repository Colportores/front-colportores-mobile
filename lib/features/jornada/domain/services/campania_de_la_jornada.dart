import '../../../../core/database/dia_de_calendario.dart';
import '../../../auth/domain/entities/campania_inscripta.dart';

/// De qué campaña es una jornada: la jornada no guarda la campaña, así que sale de la inscripción en
/// curso el día en que empezó (HU-JOR-003: «los de la campaña de su jornada»; HU-JOR-002, tendencia).
abstract final class CampaniaDeLaJornada {
  /// La campaña con inscripción viva que estaba en curso el día de [inicio] (en Montevideo); con varias,
  /// la que empezó más tarde (y a igual inicio, la de menor id, para que no cambie entre lecturas). `null`
  /// si ninguna cubre ese día o si no se pudo leer ([inscripciones] en `null`).
  static CampaniaInscripta? de(Iterable<CampaniaInscripta>? inscripciones, DateTime inicio) {
    if (inscripciones == null) return null;
    final dia = diaDeCalendario(inicio);
    final enCurso = inscripciones.where((c) => c.enCursoA(dia)).toList()
      ..sort(
        (a, b) => switch (b.fechaInicio.compareTo(a.fechaInicio)) {
          0 => a.campaniaId.compareTo(b.campaniaId),
          final porFecha => porFecha,
        },
      );
    return enCurso.isEmpty ? null : enCurso.first;
  }
}

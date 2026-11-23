import 'package:equatable/equatable.dart';

import '../entities/campania_inscripta.dart';

/// La campaña que todavía no empezó y por la que la app frena la jornada y la venta (HU-AUTH-008,
/// decisión de Cristian del 23/10, «Cuenta antes»).
class CampaniaPorEmpezar extends Equatable {
  const CampaniaPorEmpezar({required this.nombre, required this.fechaInicio});

  final String nombre;

  /// El primer día de la campaña, `AAAA-MM-DD`.
  final String fechaInicio;

  /// El día de inicio como «dd/mm», que es como lo dice el aviso.
  String get diaYMes => diaYMesDe(fechaInicio);

  @override
  List<Object?> get props => [nombre, fechaInicio];
}

/// «dd/mm» de un día `AAAA-MM-DD`.
String diaYMesDe(String fecha) {
  final partes = fecha.split('-');
  if (partes.length != 3) return fecha;
  return '${partes[2]}/${partes[1]}';
}

/// Las reglas de qué campaña le toca al colportor hoy, a partir de lo que el teléfono sabe de sus
/// inscripciones. Solo mira fechas: el estado de la cuenta lo decide el servidor.
abstract final class SituacionDeCampania {
  /// La campaña por empezar que frena la jornada y la venta de hoy, o `null` si no frena nada.
  ///
  /// Frena solo con **una inscripción en una campaña que empieza después de [hoy] y ninguna en
  /// curso** (la misma regla de la HU y del servidor, 0102 y 0115). Con más de una por empezar, la
  /// que empieza primero. Sin inscripciones, o con una campaña en curso, no frena nada.
  static CampaniaPorEmpezar? porEmpezar(
    Iterable<CampaniaInscripta> inscripciones, {
    required String hoy,
  }) {
    if (inscripciones.any((c) => c.enCursoA(hoy))) return null;
    final proxima = _masProxima(inscripciones.where((c) => !c.empezoA(hoy)));
    return proxima == null
        ? null
        : CampaniaPorEmpezar(nombre: proxima.nombre, fechaInicio: proxima.fechaInicio);
  }

  /// La campaña a la que se asignó al colportor, para «Ya te asignaron»: la que está en curso o, si
  /// no hay, la que empieza primero. Las que ya terminaron no cuentan. Con dos en curso, la que
  /// empezó última (la más reciente).
  static CampaniaInscripta? vigenteOProxima(
    Iterable<CampaniaInscripta> inscripciones, {
    required String hoy,
  }) {
    final enCurso = inscripciones.where((c) => c.enCursoA(hoy)).toList()
      ..sort(
        (a, b) => switch (b.fechaInicio.compareTo(a.fechaInicio)) {
          0 => a.campaniaId.compareTo(b.campaniaId),
          final porFecha => porFecha,
        },
      );
    if (enCurso.isNotEmpty) return enCurso.first;
    return _masProxima(inscripciones.where((c) => !c.empezoA(hoy)));
  }

  /// La campaña de [inscripciones] a la que le tocó frenar una jornada del día [dia]: la que empieza
  /// primero después de ese día. `null` si ninguna empieza después.
  static CampaniaInscripta? queFrenoElDia(Iterable<CampaniaInscripta> inscripciones, String dia) =>
      _masProxima(inscripciones.where((c) => c.fechaInicio.compareTo(dia) > 0));

  static CampaniaInscripta? _masProxima(Iterable<CampaniaInscripta> campanias) {
    CampaniaInscripta? elegida;
    for (final c in campanias) {
      if (elegida == null) {
        elegida = c;
        continue;
      }
      final orden = c.fechaInicio.compareTo(elegida.fechaInicio);
      if (orden < 0 || (orden == 0 && c.campaniaId.compareTo(elegida.campaniaId) < 0)) elegida = c;
    }
    return elegida;
  }
}

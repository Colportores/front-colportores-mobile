import 'package:equatable/equatable.dart';

import 'ubicacion.dart';

/// Por qué dos ubicaciones son un posible duplicado (HU-UBI-006, regla del 29/09 en #207).
///
/// Si se cumplen las dos, cuenta [mismaDireccion]: es la más fuerte y la que decide si se puede
/// "conservar ambos": a menos de 100 m no, a 100 m o más sí (D1, ver
/// `CriterioDuplicadoUbicacion.radioMismaDireccionMetros`).
enum MotivoDuplicado {
  /// Misma calle y mismo número en la misma ciudad, a cualquier distancia (el GPS puede diferir
  /// 10 o 20 m, y dos casas con el mismo número pueden estar a cuadras). Vista 10: "Misma calle y
  /// número".
  mismaDireccion,

  /// A menos de 5 m, con cualquier dirección o sin ella. Vista 10: "A menos de 5 m".
  cercania,
}

/// Lo que el colportor decidió sobre un par del scan que no se da de baja (HU-UBI-006). Las dos
/// sacan el par de "Posibles duplicados" durante `ConsultarParesDuplicadosUseCase.ventana`.
enum DecisionParDuplicado {
  /// "Conservar ambos": son lugares distintos. Solo si el par lo admite
  /// ([ParDuplicado.admiteConservarAmbos]). Cuenta como falso positivo (R21).
  conservarAmbos,

  /// "Ignorar": no lo resuelve ahora.
  ignorar,
}

/// Una ubicación que ya existe y parece la misma que otra (alta, modificación o scan).
final class CandidataDuplicado extends Equatable {
  const CandidataDuplicado({
    required this.ubicacion,
    required this.motivo,
    required this.distanciaMetros,
    required this.admiteConservarAmbos,
  });

  final Ubicacion ubicacion;

  final MotivoDuplicado motivo;

  /// Entre los dos puntos (vista 04: "Ya existe una ubicación a 12 m").
  final double distanciaMetros;

  /// Si se puede seguir con las dos: "Crear igual" en el alta, "seguir igual" al modificar y
  /// "Conservar ambos" en el scan. Si es `false`, la salida es abrir la existente o marcar el
  /// duplicado.
  final bool admiteConservarAmbos;

  @override
  List<Object?> get props => [ubicacion, motivo, distanciaMetros, admiteConservarAmbos];
}

/// Un par de ubicaciones propias que el scan de duplicados propone revisar (HU-UBI-006, vista 10).
///
/// [a] es la que se propone conservar y [b] la que se daría de baja; la pantalla deja
/// intercambiarlas (caso borde de la HU: "permitir elegir cuál conservar"). Hoy [a] es la más
/// vieja: la vista 10 propone la de más visitas, y las visitas todavía no están en el teléfono.
final class ParDuplicado extends Equatable {
  const ParDuplicado({
    required this.a,
    required this.b,
    required this.motivo,
    required this.distanciaMetros,
    required this.admiteConservarAmbos,
  });

  final Ubicacion a;
  final Ubicacion b;
  final MotivoDuplicado motivo;
  final double distanciaMetros;

  /// Ver [CandidataDuplicado.admiteConservarAmbos].
  final bool admiteConservarAmbos;

  /// Identifica el par sin importar el orden de [a] y [b]: es la clave con la que se guarda lo
  /// que el colportor decidió ("Conservar ambos", "Ignorar").
  String get clave => claveDe(a.id, b.id);

  /// La clave del par formado por [id1] e [id2], en cualquier orden.
  static String claveDe(String id1, String id2) =>
      id1.compareTo(id2) <= 0 ? '$id1|$id2' : '$id2|$id1';

  @override
  List<Object?> get props => [a, b, motivo, distanciaMetros, admiteConservarAmbos];
}

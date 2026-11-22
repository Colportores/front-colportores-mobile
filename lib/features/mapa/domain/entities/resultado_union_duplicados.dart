import 'package:equatable/equatable.dart';

/// Lo que hizo la unión de un par de duplicados en el teléfono (HU-UBI-006).
final class ResultadoUnionDuplicados extends Equatable {
  const ResultadoUnionDuplicados({
    required this.escribio,
    this.espaciosPasados = 0,
    this.espaciosFundidos = 0,
    this.conservadaPasoAEdificio = false,
  });

  /// Nada que unir: la duplicada ya estaba de baja y sin espacios (dos toques que se pisaron, o el
  /// sync trajo la unión de otro teléfono). No encoló nada.
  static const yaUnida = ResultadoUnionDuplicados(escribio: false);

  /// Si escribió algo (y encoló el trabajo de sync). `false` = [yaUnida].
  final bool escribio;

  /// Espacios de la duplicada que pasaron a la conservada tal cual.
  final int espaciosPasados;

  /// Espacios únicos de la duplicada (sin `numero_depto`) que se fundieron en el único de la
  /// conservada: el de la duplicada quedó de baja.
  final int espaciosFundidos;

  /// La conservada era una casa y quedó con más de un espacio: pasó a edificio.
  final bool conservadaPasoAEdificio;

  @override
  List<Object?> get props => [escribio, espaciosPasados, espaciosFundidos, conservadaPasoAEdificio];
}

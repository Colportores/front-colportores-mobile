import 'package:equatable/equatable.dart';

/// Una ciudad de una campaña de la colportora cuyos precios puede consultar (vista 26).
///
/// Es una **ciudad dentro de una campaña** (`campania_ciudad`): es la clave de las excepciones de
/// precio (`precio_por_ciudad.campania_ciudad_id`). La misma ciudad en dos campañas son dos
/// [CiudadConsultable].
final class CiudadConsultable extends Equatable {
  const CiudadConsultable({
    required this.campaniaCiudadId,
    required this.ciudadId,
    required this.nombre,
    required this.campaniaNombre,
  });

  /// `campania_ciudad.id`: con él se leen las excepciones de precio.
  final String campaniaCiudadId;

  /// `ciudad.id`: con él se compara contra la ciudad del GPS y la de la zona.
  final String ciudadId;

  /// «Montevideo».
  final String nombre;

  /// «Primavera 2026»: la campaña de esta ciudad, para distinguirla al elegir otra.
  final String campaniaNombre;

  @override
  List<Object?> get props => [campaniaCiudadId, ciudadId, nombre, campaniaNombre];
}

/// Una campaña en la que la colportora está inscripta y que ya terminó: sus precios ya no se usan.
final class CampaniaTerminada extends Equatable {
  const CampaniaTerminada({required this.nombre, required this.terminoEl});

  final String nombre;

  /// El último día de la campaña.
  final DateTime terminoEl;

  @override
  List<Object?> get props => [nombre, terminoEl];
}

/// Lo que el teléfono sabe de las ciudades de la colportora para consultar precios.
final class ContextoDeCiudades extends Equatable {
  const ContextoDeCiudades({
    this.ciudades = const [],
    this.ciudadDeMiZonaId,
    this.campaniaTerminada,
  });

  /// Las ciudades de sus campañas **en curso o por empezar** con inscripción viva; las terminadas no
  /// cuentan.
  final List<CiudadConsultable> ciudades;

  /// `ciudad.id` de la zona que tiene asignada; `null` si no tiene zona.
  final String? ciudadDeMiZonaId;

  /// La campaña terminada más reciente, para decirle por qué no hay precios cuando [ciudades] está
  /// vacía y solo tiene campañas terminadas (26·11).
  final CampaniaTerminada? campaniaTerminada;

  /// La ciudad con el id [ciudadId] (la del GPS o la de la zona), o `null` si no es de sus campañas.
  CiudadConsultable? deLaCiudad(String? ciudadId) {
    if (ciudadId == null) return null;
    for (final ciudad in ciudades) {
      if (ciudad.ciudadId == ciudadId) return ciudad;
    }
    return null;
  }

  @override
  List<Object?> get props => [ciudades, ciudadDeMiZonaId, campaniaTerminada];
}

/// Por dónde llegó la ciudad con la que abre Precios (decisión de Cristian, 23/10, «Precios GPS»).
enum OrigenDeLaCiudad {
  /// Donde está la colportora, por el GPS (26·01): «SEGÚN DÓNDE ESTÁS».
  gps,

  /// La ciudad de su zona, porque no hay GPS (26·06): «CIUDAD DE TU ZONA · SIN GPS».
  zona,

  /// La eligió ella en «Ver otra ciudad» (26·04 y 26·05).
  elegida,
}

/// La ciudad con la que abre Precios y de dónde sale; [ciudad] `null` = no hay una (sin zona ni GPS:
/// la elige ella).
final class CiudadInicial extends Equatable {
  const CiudadInicial(this.ciudad, this.origen);

  /// Sin ciudad todavía: ni GPS en una ciudad de sus campañas ni zona asignada.
  const CiudadInicial.ninguna() : ciudad = null, origen = null;

  final CiudadConsultable? ciudad;
  final OrigenDeLaCiudad? origen;

  @override
  List<Object?> get props => [ciudad, origen];
}

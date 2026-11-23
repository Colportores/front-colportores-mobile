import 'package:equatable/equatable.dart';

/// Una campaña en la que el colportor tiene una inscripción viva, con lo que la app muestra de ella
/// (HU-AUTH-008): el nombre, las fechas y la zona asignada, si tiene una. La lee el teléfono de las
/// réplicas del pull de catálogos (`campania_colportor`, `campania`, `zona` y `ciudad`); nunca la
/// escribe.
///
/// Las fechas son días de calendario de Montevideo, `AAAA-MM-DD`, y se comparan como texto (ver
/// `diaDeCalendario`): un día no es un instante.
class CampaniaInscripta extends Equatable {
  const CampaniaInscripta({
    required this.campaniaId,
    required this.nombre,
    required this.fechaInicio,
    this.fechaFin,
    this.zona,
    this.ciudad,
  });

  final String campaniaId;

  /// Nombre de la campaña, tal cual la cargó el coordinador.
  final String nombre;

  /// Primer día de la campaña, `AAAA-MM-DD`.
  final String fechaInicio;

  /// Último día de la campaña (inclusive), `AAAA-MM-DD`; `null` = sin fin (campaña permanente).
  final String? fechaFin;

  /// Nombre de la zona asignada, o `null`: está inscripto «sin zona», o la zona todavía no llegó a la
  /// réplica.
  final String? zona;

  /// Nombre de la ciudad de [zona], o `null` si no se conoce.
  final String? ciudad;

  /// La campaña ya empezó a [hoy] (`AAAA-MM-DD`): hoy es su primer día o uno posterior.
  bool empezoA(String hoy) => fechaInicio.compareTo(hoy) <= 0;

  /// La campaña ya terminó a [hoy]: su último día fue antes.
  bool terminoA(String hoy) => fechaFin != null && fechaFin!.compareTo(hoy) < 0;

  /// En curso a [hoy]: empezó y todavía no terminó.
  bool enCursoA(String hoy) => empezoA(hoy) && !terminoA(hoy);

  @override
  List<Object?> get props => [campaniaId, nombre, fechaInicio, fechaFin, zona, ciudad];
}

import 'package:equatable/equatable.dart';

/// A qué campaña y zona asignó el coordinador al colportor (vista 18, 18-A07 «Ya te asignaron»):
/// «Campaña Primavera 2026» y «Zona Centro · Montevideo».
class AsignacionCampania extends Equatable {
  const AsignacionCampania({required this.campania, this.zona, this.ciudad});

  /// Nombre de la campaña, tal cual la cargó el coordinador.
  final String campania;

  /// Nombre de la zona, sin el prefijo «Zona». `null` si está inscripto «sin zona» o la zona todavía
  /// no llegó al teléfono: el renglón no se muestra, no se inventa.
  final String? zona;

  /// La ciudad de [zona], o `null` si no se conoce.
  final String? ciudad;

  @override
  List<Object?> get props => [campania, zona, ciudad];
}

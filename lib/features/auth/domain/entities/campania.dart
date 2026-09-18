import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Período de actividad de colportaje (esquema-datos.md §Identidad, tabla `campania`).
enum TipoCampania { verano, invierno, permanente }

class Campania extends Equatable {
  const Campania({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.fechaInicio,
    required this.fechaFin,
    required this.ciudadId,
    this.coordinadorId,
    required this.auditoria,
  });

  final String id;
  final String nombre;
  final TipoCampania tipo;
  final DateTime fechaInicio;
  final DateTime fechaFin;

  /// FK a `ciudad.id` (entidad de Geografía, fuera del alcance de #8 — se referencia por id).
  final String ciudadId;

  /// FK a `usuario.id`. Nullable: puede asignarse después de crear la campaña.
  final String? coordinadorId;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [
    id,
    nombre,
    tipo,
    fechaInicio,
    fechaFin,
    ciudadId,
    coordinadorId,
    auditoria,
  ];
}

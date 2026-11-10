import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Período de actividad de colportaje (esquema-datos.md §Identidad, tabla `campania`).
enum TipoCampania { verano, invierno, permanente }

class Campania extends Equatable {
  Campania({
    required this.id,
    required this.nombre,
    required this.tipo,
    required DateTime fechaInicio,
    DateTime? fechaFin,
    required this.ciudadId,
    this.coordinadorId,
    required this.auditoria,
  }) : assert(
         fechaFin == null || !fechaFin.isBefore(fechaInicio),
         'fechaFin no puede ser anterior a fechaInicio (check del backend)',
       ),
       fechaInicio = fechaInicio.toUtc(),
       fechaFin = fechaFin?.toUtc();

  final String id;
  final String nombre;
  final TipoCampania tipo;

  /// Siempre en UTC — ver el invariante de fechas en [Auditoria].
  final DateTime fechaInicio;

  /// `null` si la campaña es permanente, que por definición no termina (esquema-datos.md
  /// §Identidad): nadie debe inventar un centinela (año 9999, etc.). Si tiene valor, nunca es
  /// anterior a [fechaInicio] (`check (fecha_fin is null or fecha_fin >= fecha_inicio)`).
  /// Siempre en UTC — ver el invariante de fechas en [Auditoria].
  final DateTime? fechaFin;

  /// FK a `ciudad.id` (entidad de Geografía, fuera del alcance de #8 — se referencia por id).
  final String ciudadId;

  /// FK opcional a `usuario.id`: se asigna después de crear la campaña (esquema-datos.md
  /// §Identidad), así que puede ser `null`.
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

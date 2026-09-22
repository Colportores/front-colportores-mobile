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
    required DateTime fechaFin,
    required this.ciudadId,
    this.coordinadorId,
    required this.auditoria,
  }) : fechaInicio = fechaInicio.toUtc(),
       fechaFin = fechaFin.toUtc();

  final String id;
  final String nombre;
  final TipoCampania tipo;

  /// Siempre en UTC — ver el invariante de fechas en [Auditoria].
  final DateTime fechaInicio;

  /// Siempre en UTC — ver el invariante de fechas en [Auditoria].
  ///
  /// TODO(#8): no-nullable aun con [TipoCampania.permanente], que por definición no tiene fecha
  /// de fin — el llamador termina inventando un centinela. Decisión pendiente (ver comentario
  /// en el issue #8).
  final DateTime fechaFin;

  /// FK a `ciudad.id` (entidad de Geografía, fuera del alcance de #8 — se referencia por id).
  final String ciudadId;

  /// FK a `usuario.id`.
  ///
  /// TODO(#8): el esquema no lo marca como opcional (y sí marca otros: "(FK opcional)",
  /// "(nullable)"), así que hacerlo nullable es apartarse del esquema — decisión pendiente
  /// (ver comentario en el issue #8).
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

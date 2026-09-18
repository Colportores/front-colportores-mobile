import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Horarios preferidos de trabajo del colportor: turnos AM/PM + slots
/// (esquema-datos.md §Identidad, tabla `horario_colportor`).
enum DiaSemana { lunes, martes, miercoles, jueves, viernes, sabado, domingo }

class HorarioColportor extends Equatable {
  const HorarioColportor({
    required this.id,
    required this.usuarioId,
    required this.diaSemana,
    required this.slotCodigo,
    required this.auditoria,
  });

  final String id;

  /// FK a `usuario.id`.
  final String usuarioId;

  final DiaSemana diaSemana;

  /// Código de turno/slot (ej. "AM1", "PM2"). El esquema no fija un catálogo cerrado de
  /// valores — se modela como texto libre hasta que se defina uno (fuera del alcance #8).
  final String slotCodigo;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [id, usuarioId, diaSemana, slotCodigo, auditoria];
}

import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Contacto realizado por el colportor (esquema-datos.md §Operaciones de campo, tabla
/// `visita`).
enum TipoResultadoVisita { venta, noContesto, rechazo, entrevista }

class Visita extends Equatable {
  const Visita({
    required this.id,
    required this.espacioPersonaId,
    required this.fecha,
    required this.tipoResultado,
    this.notas,
    required this.colportorId,
    required this.jornadaId,
    required this.auditoria,
  });

  final String id;

  /// FK a `espacio_persona.id`.
  final String espacioPersonaId;

  final DateTime fecha;

  final TipoResultadoVisita tipoResultado;

  /// Generalmente contiene PII (esquema-datos.md, tabla de clasificación de PII) — no loguear
  /// (convenciones-desarrollo.md §7).
  final String? notas;

  /// FK a `usuario.id`.
  final String colportorId;

  /// FK a `jornada.id`.
  final String jornadaId;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [
    id,
    espacioPersonaId,
    fecha,
    tipoResultado,
    notas,
    colportorId,
    jornadaId,
    auditoria,
  ];
}

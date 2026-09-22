import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Contacto realizado por el colportor (esquema-datos.md §Operaciones de campo, tabla
/// `visita`).
enum TipoResultadoVisita { venta, noContesto, rechazo, entrevista }

class Visita extends Equatable {
  Visita({
    required this.id,
    required this.espacioPersonaId,
    required DateTime fecha,
    required this.tipoResultado,
    this.notas,
    required this.colportorId,
    required this.jornadaId,
    required this.auditoria,
  }) : fecha = fecha.toUtc();

  final String id;

  /// FK a `espacio_persona.id`.
  final String espacioPersonaId;

  /// Siempre en UTC — ver el invariante de fechas en [Auditoria].
  final DateTime fecha;

  final TipoResultadoVisita tipoResultado;

  /// Generalmente contiene PII (esquema-datos.md, tabla de clasificación de PII) — no loguear
  /// (convenciones-desarrollo.md §7.5).
  final String? notas;

  /// FK a `usuario.id`.
  final String colportorId;

  /// FK a `jornada.id`.
  final String jornadaId;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  /// [notas] está en [props] y `EquatableConfig.stringify` arranca en `true` en debug: sin esto,
  /// cualquier interpolación del objeto o `logger.d(visita)` imprimiría las notas del cliente
  /// (convenciones-desarrollo.md §7.5, "sin PII en logs: solo IDs").
  @override
  bool? get stringify => false;

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

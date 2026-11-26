import 'package:equatable/equatable.dart';

import 'estado_casa.dart';

/// Lo que la fila de un depto dice de él en la hoja del edificio (vista 39, C·09 «Edificio: sus
/// deptos»): el color y el símbolo de su estado y, para decir cuándo, la fecha de su última visita y
/// la de su próxima entrevista y el principio de su nota más nueva (vista 11, 11N·06, #290).
///
/// El [estado] es la misma cuenta que pinta la casa (ADR-003, `CalculadorColorCasa`) hecha solo con lo
/// que cuelga de ese depto: así el edificio, que toma el estado más urgente de sus deptos (decisión de
/// Cristian, 23/10, «Color edificio»), y sus filas nunca dicen cosas distintas.
class ResumenDelDepto extends Equatable {
  ResumenDelDepto({
    this.estado = EstadoCasa.sinVisita,
    DateTime? ultimaVisita,
    DateTime? proximaEntrevista,
    this.notaMasNueva,
  }) : ultimaVisita = ultimaVisita?.toUtc(),
       proximaEntrevista = proximaEntrevista?.toUtc();

  final EstadoCasa estado;

  /// Cuándo fue su última visita (UTC); `null` si no tuvo ninguna.
  final DateTime? ultimaVisita;

  /// Cuándo es su próxima entrevista programada que todavía no pasó (UTC); `null` si no hay.
  final DateTime? proximaEntrevista;

  /// El texto de la nota más nueva del depto que no esté borrada (entero: la fila corta lo que muestra);
  /// `null` si no tiene ninguna.
  ///
  /// **local-only — PII**: el texto vive solo en el teléfono y nunca va a un log.
  final String? notaMasNueva;

  /// Apagado por la misma razón que `NotaUbicacion.stringify`: un `'$resumen'` o un log con el resumen
  /// imprimiría la nota (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [estado, ultimaVisita, proximaEntrevista, notaMasNueva];
}

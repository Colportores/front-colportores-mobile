import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Período de trabajo de un colportor (esquema-datos.md §Operaciones de campo, tabla
/// `jornada`). El esquema no define una máquina de estados para esta entidad (§Estados solo
/// cubre `agenda`, `pedido_casa_editora` y `transferencia_stock`) — el "abierta/cerrada" se
/// infiere de si [fin] está asignado, no es un enum del esquema.
class Jornada extends Equatable {
  const Jornada({
    required this.id,
    required this.colportorId,
    required this.inicio,
    this.fin,
    this.acompananteId,
    this.tipoAcompanamiento,
    this.totalVisitas = 0,
    this.totalVentas = 0,
    required this.auditoria,
  });

  final String id;

  /// FK a `usuario.id`.
  final String colportorId;

  final DateTime inicio;

  /// `null` mientras la jornada está en curso.
  final DateTime? fin;

  /// FK opcional a `usuario.id` (esquema-datos.md: "acompañante_id (FK opcional)").
  final String? acompananteId;

  /// TODO(#8): el esquema no define el catálogo de valores de `tipo_acompañamiento` — pendiente
  /// de confirmar. Se modela como texto libre hasta que se defina.
  final String? tipoAcompanamiento;

  /// Denormalizado al cerrar la jornada (esquema-datos.md).
  final int totalVisitas;

  /// Denormalizado al cerrar la jornada (esquema-datos.md).
  final int totalVentas;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  bool get estaAbierta => fin == null;

  @override
  List<Object?> get props => [
    id,
    colportorId,
    inicio,
    fin,
    acompananteId,
    tipoAcompanamiento,
    totalVisitas,
    totalVentas,
    auditoria,
  ];
}

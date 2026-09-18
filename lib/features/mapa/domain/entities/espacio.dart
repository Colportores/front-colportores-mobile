import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Punto de contacto dentro de una ubicación (esquema-datos.md §Modelo de Espacio, tabla
/// `espacio`). Para casa/negocio: 1 espacio con `numeroDepto == null`; para edificio: 1 espacio
/// por departamento.
class Espacio extends Equatable {
  const Espacio({
    required this.id,
    required this.ubicacionId,
    this.numeroDepto,
    this.piso,
    this.descripcion,
    required this.auditoria,
  });

  final String id;

  /// FK a `ubicacion.id`.
  final String ubicacionId;

  /// Nullable (esquema-datos.md). Texto libre: en la práctica alfanumérico (ej. "3B").
  final String? numeroDepto;

  /// Nullable (esquema-datos.md). Texto libre por el mismo motivo que [numeroDepto]
  /// (ej. "PB", "1").
  final String? piso;

  final String? descripcion;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [id, ubicacionId, numeroDepto, piso, descripcion, auditoria];
}

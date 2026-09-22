import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Catálogo de roles del sistema (esquema-datos.md §Identidad, tabla `rol`).
///
/// Multi-rol soportado vía [UsuarioRol] (M:N usuario↔rol).
enum NombreRol { guest, colportor, coordinador, admin, asistenteFin, acompanante }

/// Rol asignable a un usuario. Entidad de dominio: Dart puro (ADR-009).
class Rol extends Equatable {
  const Rol({required this.id, required this.nombre, required this.auditoria});

  /// UUID v7 (esquema-datos.md §Principios).
  final String id;

  final NombreRol nombre;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [id, nombre, auditoria];
}

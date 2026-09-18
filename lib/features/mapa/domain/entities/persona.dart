import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Cliente del colportor (esquema-datos.md §Modelo de Espacio, tabla `persona`).
///
/// **local-only — PII**: nunca se sincroniza al cloud (esquema-datos.md §Principios 4 y tabla
/// de clasificación de PII). No loguear estos campos (convenciones-desarrollo.md §7).
class Persona extends Equatable {
  const Persona({
    required this.id,
    required this.nombre,
    required this.apellido,
    this.telefono,
    this.notasGlobales,
    required this.auditoria,
  });

  final String id;
  final String nombre;
  final String apellido;
  final String? telefono;
  final String? notasGlobales;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [id, nombre, apellido, telefono, notasGlobales, auditoria];
}

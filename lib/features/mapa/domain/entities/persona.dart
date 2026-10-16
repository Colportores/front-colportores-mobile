import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Cliente del colportor (esquema-datos.md §Modelo de Espacio, tabla `persona`).
///
/// **local-only — PII**: nunca se sincroniza al cloud (esquema-datos.md §Principios 4 y tabla
/// de clasificación de PII). No loguear estos campos (convenciones-desarrollo.md §7.5).
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

  /// `EquatableConfig.stringify` arranca en `true` en debug, así que `Equatable.toString()`
  /// imprimiría [props] — nombre, apellido, teléfono y notas del cliente — en cualquier
  /// `'$persona'`, `logger.d(persona)` o excepción que interpole el objeto. Eso viola
  /// convenciones-desarrollo.md §7.5 ("sin PII en logs: solo IDs"), así que se apaga acá y no
  /// queda a criterio de cada call site.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [id, nombre, apellido, telefono, notasGlobales, auditoria];
}

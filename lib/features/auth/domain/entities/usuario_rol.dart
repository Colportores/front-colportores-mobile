import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Asociación M:N usuario ↔ rol, con vigencia temporal para roles temporales
/// (esquema-datos.md §Identidad, tabla `usuario_rol`).
class UsuarioRol extends Equatable {
  const UsuarioRol({
    required this.id,
    required this.usuarioId,
    required this.rolId,
    required this.validoDesde,
    this.validoHasta,
    required this.auditoria,
  });

  final String id;

  /// FK a `usuario.id`.
  final String usuarioId;

  /// FK a `rol.id`.
  final String rolId;

  final DateTime validoDesde;

  /// `null` = sin fecha de expiración (rol permanente).
  final DateTime? validoHasta;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  /// `true` si el rol está vigente en [ahora] (por defecto, el instante actual).
  bool esVigente({DateTime? ahora}) {
    final momento = ahora ?? DateTime.now();
    if (momento.isBefore(validoDesde)) return false;
    final hasta = validoHasta;
    if (hasta != null && momento.isAfter(hasta)) return false;
    return true;
  }

  @override
  List<Object?> get props => [id, usuarioId, rolId, validoDesde, validoHasta, auditoria];
}

import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Asociación M:N usuario ↔ rol, con vigencia temporal para roles temporales
/// (esquema-datos.md §Identidad, tabla `usuario_rol`).
class UsuarioRol extends Equatable {
  UsuarioRol({
    required this.id,
    required this.usuarioId,
    required this.rolId,
    required DateTime validoDesde,
    DateTime? validoHasta,
    required this.auditoria,
  }) : validoDesde = validoDesde.toUtc(),
       validoHasta = validoHasta?.toUtc();

  final String id;

  /// FK a `usuario.id`.
  final String usuarioId;

  /// FK a `rol.id`.
  final String rolId;

  /// Siempre en UTC — ver el invariante de fechas en [Auditoria].
  final DateTime validoDesde;

  /// `null` = sin fecha de expiración (rol permanente).
  /// Siempre en UTC — ver el invariante de fechas en [Auditoria].
  final DateTime? validoHasta;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  /// `true` si el rol está vigente en [ahora] (por defecto, el instante actual).
  ///
  /// Un rol revocado es un soft delete (esquema-datos.md §Principios 6: no hay borrado físico,
  /// revocar es setear `deleted_at`), y eso no toca [validoDesde]/[validoHasta]. Si esto solo
  /// mirara la ventana temporal, un `if (rol.esVigente())` seguiría otorgando un permiso ya
  /// revocado.
  bool esVigente({DateTime? ahora}) {
    if (estaBorrada) return false;
    final momento = ahora ?? DateTime.now();
    if (momento.isBefore(validoDesde)) return false;
    final hasta = validoHasta;
    if (hasta != null && momento.isAfter(hasta)) return false;
    return true;
  }

  @override
  List<Object?> get props => [id, usuarioId, rolId, validoDesde, validoHasta, auditoria];
}

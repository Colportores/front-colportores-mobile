import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Operación comercial (esquema-datos.md §Operaciones de campo, tabla `venta`).
///
/// Regla de integridad "una venta debe tener al menos un `venta_item`" (esquema-datos.md
/// §Reglas de integridad) NO se valida en este constructor: el esquema modela `venta_item`
/// con `venta_id` como FK (dueño del lado N), no como una lista dentro de `venta`, y esta
/// entidad no anida objetos de otras tablas (regla 5.6.3). Se enforcea en el
/// repositorio/caso de uso que persiste `Venta` junto con sus `VentaItem`.
///
/// El dinero va en centavos como `int`, nunca `double` (flutter-clean-arch.md, regla 6).
class Venta extends Equatable {
  Venta({
    required this.id,
    required this.espacioPersonaId,
    required this.numeroTalonario,
    required this.montoTotalCentavos,
    required DateTime fecha,
    required this.colportorId,
    required this.visitaId,
    required this.auditoria,
  }) : fecha = fecha.toUtc();

  final String id;

  /// FK a `espacio_persona.id`.
  final String espacioPersonaId;

  /// El esquema no especifica el formato del talonario — se modela como texto libre.
  final String numeroTalonario;

  /// Monto total en centavos (flutter-clean-arch.md, regla 6).
  ///
  /// TODO(#8): el nombre del campo (`montoTotalCentavos` vs `montoTotal` del template de
  /// flutter-clean-arch.md) es decisión pendiente — ver comentario en el issue #8. El tipo no:
  /// centavos como `int` está decidido.
  final int montoTotalCentavos;

  /// Siempre en UTC — ver el invariante de fechas en [Auditoria].
  final DateTime fecha;

  /// FK a `usuario.id`.
  final String colportorId;

  /// FK a `visita.id`.
  final String visitaId;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [
    id,
    espacioPersonaId,
    numeroTalonario,
    montoTotalCentavos,
    fecha,
    colportorId,
    visitaId,
    auditoria,
  ];
}

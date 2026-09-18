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
/// `montoTotalCentavos`: el esquema no dice si los montos son enteros en centavos o `double`
/// (esquema-datos.md no lo especifica para `venta.monto_total`) — se usa `int` en centavos
/// por convención hasta confirmar. **Pendiente de confirmar** (ver PR).
class Venta extends Equatable {
  const Venta({
    required this.id,
    required this.espacioPersonaId,
    required this.numeroTalonario,
    required this.montoTotalCentavos,
    required this.fecha,
    required this.colportorId,
    required this.visitaId,
    required this.auditoria,
  });

  final String id;

  /// FK a `espacio_persona.id`.
  final String espacioPersonaId;

  /// El esquema no especifica el formato del talonario — se modela como texto libre.
  final String numeroTalonario;

  /// Pendiente de confirmar: ver doc comment de la clase.
  final int montoTotalCentavos;

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

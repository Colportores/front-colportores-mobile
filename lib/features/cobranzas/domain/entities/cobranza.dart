import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Cobro asociado a una venta (esquema-datos.md §Operaciones de campo, tabla `cobranza`).
///
/// Regla de integridad "un cobro debe estar asociado a una venta (`venta_id` NOT NULL en
/// `cobranza`)" (esquema-datos.md §Reglas de integridad, RF-CO01..04): se enforcea con el tipo
/// — [ventaId] es `String` no nullable, el sistema de tipos de Dart lo garantiza en compilación.
///
/// `montoCentavos`: mismo criterio que `Venta.montoTotalCentavos` — el esquema no especifica
/// el tipo del monto; se usa `int` en centavos. **Pendiente de confirmar** (ver PR).
///
/// `CobranzaItem`: el diagrama plantuml de esquema-datos.md (§Visión general de entidades)
/// menciona `CobranzaItem` y una relación `Cobranza "1" -- "N" CobranzaItem`, pero la sección
/// funcional (§Tablas — descripción funcional) no incluye una descripción de sus campos dentro
/// del alcance leído para #8. No se crea esa entidad: sería inventar campos que el esquema no
/// documenta. **Bloqueado/pendiente**: ¿cuáles son los campos de `cobranza_item`?
enum MedioCobranza { efectivo, tarjeta, transferencia }

class Cobranza extends Equatable {
  const Cobranza({
    required this.id,
    required this.ventaId,
    required this.montoCentavos,
    required this.medio,
    required this.fecha,
    this.ticketId,
    required this.numeroCuota,
    required this.auditoria,
  });

  final String id;

  /// FK a `venta.id`. NOT NULL — ver doc comment de la clase.
  final String ventaId;

  /// Pendiente de confirmar: ver doc comment de la clase.
  final int montoCentavos;

  final MedioCobranza medio;

  final DateTime fecha;

  /// FK opcional a `ticket.id` (esquema-datos.md: "ticket_id (FK opcional)").
  final String? ticketId;

  final int numeroCuota;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [
    id,
    ventaId,
    montoCentavos,
    medio,
    fecha,
    ticketId,
    numeroCuota,
    auditoria,
  ];
}

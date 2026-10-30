import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Cobro asociado a una venta (esquema-datos.md §Operaciones de campo, tabla `cobranza`).
///
/// Regla de integridad "un cobro debe estar asociado a una venta (`venta_id` NOT NULL en
/// `cobranza`)" (esquema-datos.md §Reglas de integridad, RF-CO01..04): se enforcea con el tipo
/// — [ventaId] es `String` no nullable, el sistema de tipos de Dart lo garantiza en compilación.
///
/// El monto va en centavos como `int`, nunca `double` (flutter-clean-arch.md, regla 6).
///
/// `CobranzaItem`: el diagrama plantuml de esquema-datos.md (§Visión general de entidades)
/// menciona `CobranzaItem` y una relación `Cobranza "1" -- "N" CobranzaItem`, pero la sección
/// funcional (§Tablas — descripción funcional) no incluye una descripción de sus campos dentro
/// del alcance leído para #8. No se crea esa entidad: sería inventar campos que el esquema no
/// documenta. **Bloqueado/pendiente**: ¿cuáles son los campos de `cobranza_item`?
enum MedioCobranza { efectivo, tarjeta, transferencia }

/// Si la tarjeta del cobro era de débito o de crédito (`cobranza.tarjeta_tipo`: `DEBITO` / `CREDITO`,
/// los mismos valores que `ticket`).
enum TipoTarjeta { debito, credito }

/// Por qué se anuló un cobro (HU-COB-006, vista 30 B, 30B-02): la lista del canvas. [codigo] es el texto
/// que guarda `cobranza.motivo_anulacion` y que acepta el CHECK del servidor (backend 0072); «Otro»
/// pide además un texto que se queda en el teléfono.
enum MotivoDeAnulacion {
  montoEquivocado('Monto equivocado'),
  clienteEquivocado('Cliente equivocado'),
  registreDosVeces('Lo registré dos veces'),
  otro('Otro');

  const MotivoDeAnulacion(this.codigo);

  final String codigo;

  /// El motivo de un código guardado; `null` si no hay o no se reconoce.
  static MotivoDeAnulacion? desdeCodigo(String? codigo) {
    for (final m in values) {
      if (m.codigo == codigo) return m;
    }
    return null;
  }
}

class Cobranza extends Equatable {
  Cobranza({
    required this.id,
    required this.ventaId,
    required this.montoCentavos,
    required this.medio,
    required DateTime fecha,
    this.ticketId,
    this.numeroCuota,
    this.tarjetaTipo,
    this.tarjetaMarca,
    this.numeroAprobacion,
    this.referenciaTransferencia,
    this.bancoOrigen,
    DateTime? anuladoAt,
    this.motivoAnulacion,
    required this.auditoria,
  }) : fecha = fecha.toUtc(),
       anuladoAt = anuladoAt?.toUtc();

  final String id;

  /// FK a `venta.id`. NOT NULL — ver doc comment de la clase.
  final String ventaId;

  /// Monto cobrado en centavos (flutter-clean-arch.md, regla 6).
  final int montoCentavos;

  final MedioCobranza medio;

  /// Siempre en UTC — ver el invariante de fechas en [Auditoria].
  final DateTime fecha;

  /// FK opcional a `ticket.id` (esquema-datos.md: "ticket_id (FK opcional)").
  final String? ticketId;

  /// Número de cuota (HU-COB-004); `null` si el cobro no es de una cuota (el servidor lo admite).
  final int? numeroCuota;

  /// Solo con [MedioCobranza.tarjeta] (HU-COB-002, #396): débito o crédito. Opcional.
  final TipoTarjeta? tarjetaTipo;

  /// Solo con [MedioCobranza.tarjeta]: la marca («Visa», «Mastercard», «OCA» o la que escribió la
  /// colportora), 1 a 40 caracteres. Opcional.
  final String? tarjetaMarca;

  /// Solo con [MedioCobranza.tarjeta]: el número de aprobación del ticket del POS, 1 a 40 caracteres.
  /// Opcional en V1.
  final String? numeroAprobacion;

  /// Solo con [MedioCobranza.transferencia] (HU-COB-003): el número de operación, 1 a 40 caracteres.
  /// Opcional.
  final String? referenciaTransferencia;

  /// Solo con [MedioCobranza.transferencia]: el banco de origen **como texto** (no una lista cerrada:
  /// sumar un banco no cambia el modelo), 1 a 60 caracteres. Opcional.
  final String? bancoOrigen;

  /// Cuándo se anuló (hora del teléfono, UTC), o `null` si está vigente (HU-COB-006). Un cobro anulado
  /// no se borra, no se reabre y no cuenta para el saldo ni para el color de la casa.
  final DateTime? anuladoAt;

  /// El motivo de la lista con que se anuló; va junto con [anuladoAt].
  final MotivoDeAnulacion? motivoAnulacion;

  final Auditoria auditoria;

  bool get estaAnulado => anuladoAt != null;

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
    tarjetaTipo,
    tarjetaMarca,
    numeroAprobacion,
    referenciaTransferencia,
    bancoOrigen,
    anuladoAt,
    motivoAnulacion,
    auditoria,
  ];
}

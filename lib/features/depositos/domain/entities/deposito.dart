import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';

/// A dónde fue el efectivo (`deposito.destino`, esquema-datos.md §deposito, HU-CTA-004).
enum DestinoDeDeposito {
  /// Lo depositó en un banco: lleva el ticket del banco.
  banco,

  /// Lo depositó en la oficina: lleva el ticket.
  oficina,

  /// Se lo entregó al coordinador, que lo lleva a depositar (donde no hay dónde depositar, como
  /// Artigas y Bella Unión): no hay comprobante del banco, así que no lleva ticket.
  retiroCoordinador;

  /// El depósito de banco o de oficina se registra con su ticket, en un solo paso (decisión de
  /// Cristian, 23/10, «Paso ticket»; el servidor lo exige con `23514`). El retiro por el coordinador
  /// no lleva ticket.
  bool get llevaTicket => this != retiroCoordinador;
}

/// Para qué era el dinero (`deposito.concepto`): decide contra qué deuda cuenta (HU-CTA-007). Un
/// depósito tiene un solo concepto; para pagar los dos se registran dos depósitos.
enum ConceptoDeDeposito { casaEditora, alquiler }

/// En qué quedó un depósito para el coordinador (decisión «Acredita V1», 23/10; «Rechazo ret.», 28/10).
enum EstadoDeDeposito {
  /// Registrado y todavía sin respuesta: no suma a «Depositado» ni baja la deuda.
  porValidar,

  /// El coordinador lo validó: suma a «Depositado» y baja la deuda.
  validado,

  /// El coordinador lo rechazó (hoy, un retiro sin ticket) y dejó su motivo: no suma a nada, la plata
  /// vuelve a estar «en mano» y el colportor carga uno corregido.
  rechazado,
}

/// Un depósito de efectivo del colportor (esquema-datos.md §deposito, HU-CTA-004).
///
/// Se da de alta desde el teléfono y no se edita ni se borra. Nace **«por validar»**: no suma a
/// «Depositado» ni baja la deuda hasta que lo valida el coordinador (decisión «Acredita V1»). Esa
/// validación (`validado_en`, `validado_por`) y el rechazo de un retiro (`rechazado_en`,
/// `motivo_rechazo`) los pone el servidor y bajan al teléfono por el pull (`deposito` es `push` con
/// `alsoPull`, backend-supabase#231): el teléfono nunca los escribe ni los sube, y [estado] se calcula
/// con ellos. **No marca qué cobros incluye** (decisión del 28/10, «Cobro en dep.»): lleva el monto.
///
/// El dinero va en **centavos**. El colportor sale de la sesión y no viaja en el sync (el servidor
/// lo toma del JWT): acá es el `created_by` de la [auditoria].
class Deposito extends Equatable {
  Deposito({
    required this.id,
    required this.montoCentavos,
    required DateTime fecha,
    required this.destino,
    required this.concepto,
    this.campaniaId,
    this.ticketId,
    DateTime? validadoEn,
    this.validadoPor,
    DateTime? rechazadoEn,
    this.motivoRechazo,
    required this.auditoria,
  }) : fecha = instanteMs(fecha),
       validadoEn = validadoEn == null ? null : instanteMs(validadoEn),
       rechazadoEn = rechazadoEn == null ? null : instanteMs(rechazadoEn);

  final String id;

  /// Lo depositado, en centavos; siempre mayor que cero.
  final int montoCentavos;

  /// Cuándo se depositó (UTC).
  final DateTime fecha;

  final DestinoDeDeposito destino;
  final ConceptoDeDeposito concepto;

  /// La campaña a la que paga: obligatoria con [ConceptoDeDeposito.alquiler] (el saldo de alquiler es
  /// uno por campaña, decisión «Alq. campaña»); con casa editora puede ir o no.
  final String? campaniaId;

  /// El ticket del banco que respalda el depósito; solo con [DestinoDeDeposito.llevaTicket].
  final String? ticketId;

  /// Cuándo lo validó el coordinador (UTC); `null` si todavía no. Lo pone el servidor.
  final DateTime? validadoEn;

  /// Quién lo validó (id opaco). Lo pone el servidor.
  final String? validadoPor;

  /// Cuándo lo rechazó el coordinador (UTC); `null` si no lo rechazó. Lo pone el servidor.
  final DateTime? rechazadoEn;

  /// Por qué lo rechazó, con las palabras del coordinador. Texto libre: nunca va a un log.
  final String? motivoRechazo;

  final Auditoria auditoria;

  bool get estaBorrado => auditoria.estaBorrada;

  /// `EquatableConfig.stringify` arranca en `true` en debug: `'$deposito'` imprimiría [props], y entre
  /// ellos el [motivoRechazo], que es texto libre del coordinador (puede nombrar a una persona).
  /// convenciones-desarrollo.md §7.5 ("sin PII en logs: solo IDs"): se apaga acá y no queda a criterio
  /// de cada call site (QA #596).
  @override
  bool? get stringify => false;

  /// Por validar, validado o rechazado, según lo que bajó del servidor. **Rechazado gana**: si por un
  /// error llegaran las dos marcas, no se acredita (ante la duda no se suma plata que no está).
  EstadoDeDeposito get estado {
    if (rechazadoEn != null) return EstadoDeDeposito.rechazado;
    if (validadoEn != null) return EstadoDeDeposito.validado;
    return EstadoDeDeposito.porValidar;
  }

  @override
  List<Object?> get props => [
    id,
    montoCentavos,
    fecha,
    destino,
    concepto,
    campaniaId,
    ticketId,
    validadoEn,
    validadoPor,
    rechazadoEn,
    motivoRechazo,
    auditoria,
  ];
}

/// El depósito ya guardado.
final class DepositoRegistrado extends Equatable {
  const DepositoRegistrado({required this.deposito, this.yaEstaba = false});

  final Deposito deposito;

  /// El depósito ya estaba guardado con ese `id` (un doble toque o un reintento): no se escribió ni se
  /// encoló nada de nuevo.
  final bool yaEstaba;

  @override
  List<Object?> get props => [deposito, yaEstaba];
}

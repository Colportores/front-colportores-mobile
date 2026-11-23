import 'package:equatable/equatable.dart';

import '../../../depositos/domain/entities/deposito.dart';
import 'ticket.dart';

/// Dónde se hizo lo que dice el ticket (la primera parte de «HOY · BANCO», vista 38B·01).
enum LugarDelTicket {
  banco,
  oficina,

  /// El coordinador retiró el efectivo (sin ticket del banco).
  retiro,

  /// El ticket del POS de un cobro con tarjeta (HU-COB-007).
  cobroConTarjeta,

  /// Un ticket de depósito cuyo depósito todavía no bajó al teléfono: no se sabe si fue en el banco o
  /// en la oficina.
  deposito,
  otro,
}

/// En qué quedó un ticket para el colportor (los cuatro estados de 38B·01 y 38B·06).
enum EstadoDelItem {
  /// Todavía no llegó al servidor: espera la conexión (38B·06, «Se envía cuando vuelva la red»).
  enCola,

  /// Llegó y el coordinador todavía no respondió.
  porValidar,
  validado,
  rechazado,

  /// El coordinador devolvió la plata de un pago de alquiler que ya había validado (`anulado_at`): no
  /// suma a nada. La fila queda en el historial (nunca se pierde un registro).
  devuelto,
}

/// Qué filtro de los chips de 38B·01 está elegido.
enum FiltroDeTickets {
  todos,
  porValidar,
  rechazados,
  alquiler;

  /// Si [item] entra en este filtro. «Por validar» incluye lo que todavía está en cola: tampoco lo
  /// validó nadie.
  bool acepta(ItemDelHistorial item) => switch (this) {
    FiltroDeTickets.todos => true,
    FiltroDeTickets.porValidar =>
      item.estado == EstadoDelItem.porValidar || item.estado == EstadoDelItem.enCola,
    FiltroDeTickets.rechazados => item.estado == EstadoDelItem.rechazado,
    FiltroDeTickets.alquiler => item.concepto == ConceptoDeDeposito.alquiler,
  };
}

/// Una fila de «Mis tickets» (vista 38B, HU-COB-009): un depósito con su ticket, un retiro por el
/// coordinador (sin ticket) o el ticket de un cobro con tarjeta.
///
/// Es una lectura del teléfono: se arma con lo que bajó del servidor y lo que se registró acá, así que
/// se ve sin conexión. **Sin dato del cliente**: solo montos, fechas, el número de autorización y el
/// motivo del rechazo, que es texto libre del coordinador (nunca va a un log: [stringify] apagado).
final class ItemDelHistorial extends Equatable {
  const ItemDelHistorial({
    required this.id,
    required this.fecha,
    required this.montoCentavos,
    required this.lugar,
    required this.estado,
    this.concepto,
    this.ticketId,
    this.depositoId,
    this.numeroAutorizacion,
    this.tarjetaTipo,
    this.motivoRechazo,
    this.validadoEn,
    this.fotoSubida = false,
    this.hayCopiaLocal = false,
    this.fotoRechazada = false,
  });

  /// Un depósito con su ticket (`null` en un retiro por el coordinador) y la copia local de la foto.
  factory ItemDelHistorial.deDeposito(
    Deposito deposito, {
    Ticket? ticket,
    FotoLocalDeTicket? foto,
  }) {
    final rechazado = deposito.rechazadoEn != null || ticket?.estado == EstadoDeTicket.rechazado;
    // Un pago devuelto (`anulado_at`) no es validado ni «se acreditó»: lo anuló el coordinador.
    final devuelto = deposito.anuladoAt != null && !rechazado;
    final validado =
        !devuelto && (deposito.validadoEn != null || ticket?.estado == EstadoDeTicket.validado);
    final sinLlegar =
        deposito.auditoria.syncVersion == 0 ||
        (ticket != null && ticket.auditoria.syncVersion == 0);
    return ItemDelHistorial(
      id: deposito.id,
      depositoId: deposito.id,
      ticketId: ticket?.id,
      fecha: deposito.fecha,
      montoCentavos: deposito.montoCentavos,
      lugar: switch (deposito.destino) {
        DestinoDeDeposito.banco => LugarDelTicket.banco,
        DestinoDeDeposito.oficina => LugarDelTicket.oficina,
        DestinoDeDeposito.retiroCoordinador => LugarDelTicket.retiro,
      },
      concepto: deposito.concepto,
      estado: rechazado
          ? EstadoDelItem.rechazado
          : devuelto
          ? EstadoDelItem.devuelto
          : validado
          ? EstadoDelItem.validado
          : sinLlegar
          ? EstadoDelItem.enCola
          : EstadoDelItem.porValidar,
      numeroAutorizacion: ticket?.numeroAutorizacion,
      tarjetaTipo: ticket?.tarjetaTipo,
      motivoRechazo: rechazado
          ? _motivo(ticket?.motivoRechazo) ?? _motivo(deposito.motivoRechazo)
          : null,
      validadoEn: validado && !rechazado ? deposito.validadoEn ?? ticket?.revisadoEn : null,
      fotoSubida: ticket?.fotoSubida ?? false,
      hayCopiaLocal: foto?.hayCopiaLocal ?? false,
      fotoRechazada: foto?.estado == EstadoDeSubida.rechazada,
    );
  }

  /// Un ticket que ningún depósito nombra: el de un cobro con tarjeta, o el de un depósito que todavía
  /// no bajó.
  factory ItemDelHistorial.deTicket(Ticket ticket, {FotoLocalDeTicket? foto}) {
    return ItemDelHistorial(
      id: ticket.id,
      ticketId: ticket.id,
      fecha: ticket.fecha,
      montoCentavos: ticket.montoCentavos,
      lugar: switch (ticket.tipo) {
        TipoDeTicket.cobroTarjeta => LugarDelTicket.cobroConTarjeta,
        TipoDeTicket.deposito => LugarDelTicket.deposito,
        TipoDeTicket.otro => LugarDelTicket.otro,
      },
      estado: switch (ticket.estado) {
        EstadoDeTicket.rechazado => EstadoDelItem.rechazado,
        EstadoDeTicket.validado => EstadoDelItem.validado,
        EstadoDeTicket.pendiente =>
          ticket.auditoria.syncVersion == 0 ? EstadoDelItem.enCola : EstadoDelItem.porValidar,
      },
      numeroAutorizacion: ticket.numeroAutorizacion,
      tarjetaTipo: ticket.tarjetaTipo,
      motivoRechazo: ticket.estado == EstadoDeTicket.rechazado
          ? _motivo(ticket.motivoRechazo)
          : null,
      validadoEn: ticket.estado == EstadoDeTicket.validado ? ticket.revisadoEn : null,
      fotoSubida: ticket.fotoSubida,
      hayCopiaLocal: foto?.hayCopiaLocal ?? false,
      fotoRechazada: foto?.estado == EstadoDeSubida.rechazada,
    );
  }

  static String? _motivo(String? texto) {
    final limpio = texto?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }

  /// El id del depósito si lo hay y, si no, el del ticket.
  final String id;

  /// El ticket de la fila; `null` en un retiro por el coordinador.
  final String? ticketId;
  final String? depositoId;

  /// Cuándo se depositó o se sacó el ticket (UTC).
  final DateTime fecha;
  final int montoCentavos;
  final LugarDelTicket lugar;

  /// Para qué era el dinero; `null` en el ticket de un cobro con tarjeta.
  final ConceptoDeDeposito? concepto;
  final EstadoDelItem estado;
  final String? numeroAutorizacion;
  final TipoDeTarjeta? tarjetaTipo;

  /// Por qué lo rechazó el coordinador, con sus palabras. Texto libre: nunca a un log.
  final String? motivoRechazo;

  /// Cuándo lo validó el coordinador (UTC).
  final DateTime? validadoEn;

  /// La foto ya está en la nube.
  final bool fotoSubida;

  /// La copia de la foto sigue en el teléfono.
  final bool hayCopiaLocal;

  /// El servidor rechazó la foto para siempre (más de 2 MiB, tipo que no acepta).
  final bool fotoRechazada;

  /// Se puede volver a cargar: un depósito o un retiro rechazado. El ticket de un cobro con tarjeta se
  /// carga desde el cobro (vista 29), no desde acá.
  bool get sePuedeCargarDeNuevo =>
      estado == EstadoDelItem.rechazado &&
      depositoId != null &&
      (lugar == LugarDelTicket.banco ||
          lugar == LugarDelTicket.oficina ||
          lugar == LugarDelTicket.retiro);

  /// `EquatableConfig.stringify` arranca en `true` en debug y [motivoRechazo] es texto libre de otra
  /// persona (convenciones-desarrollo.md §7.5): `'$item'` no lo imprime.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    id,
    ticketId,
    depositoId,
    fecha,
    montoCentavos,
    lugar,
    concepto,
    estado,
    numeroAutorizacion,
    tarjetaTipo,
    motivoRechazo,
    validadoEn,
    fotoSubida,
    hayCopiaLocal,
    fotoRechazada,
  ];
}

/// Lo que muestra «Mis tickets»: las filas, la más nueva primero, y cuándo bajó del servidor la última
/// vez (para decir de cuándo son los estados sin conexión).
final class HistorialDeTickets extends Equatable {
  const HistorialDeTickets({required this.items, this.bajadoEn});

  final List<ItemDelHistorial> items;

  /// La última bajada del servidor (UTC); `null` si el teléfono todavía no bajó nada.
  final DateTime? bajadoEn;

  int get porValidar => items.where((i) => FiltroDeTickets.porValidar.acepta(i)).length;

  @override
  List<Object?> get props => [items, bajadoEn];
}

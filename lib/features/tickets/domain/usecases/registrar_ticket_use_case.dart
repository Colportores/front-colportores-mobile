import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/ticket.dart';
import '../repositories/ticket_repository.dart';
import '../services/reglas_de_ticket.dart';

/// Parámetros de [RegistrarTicketUseCase].
final class RegistrarTicketParams extends Equatable {
  const RegistrarTicketParams({
    required this.ticketId,
    required this.colportorId,
    required this.tipo,
    required this.montoCentavos,
    required this.foto,
    required this.tipoDeImagen,
    this.fecha,
    this.numeroAutorizacion,
    this.tarjetaTipo,
    this.tarjetaMarca,
    this.cobroId,
  });

  /// El id del ticket: lo genera quien abre la pantalla y se repite en los reintentos, así un doble
  /// toque o un reintento tras una falla no registra dos tickets.
  final String ticketId;

  /// Quién carga el ticket: el `created_by` de la fila.
  final String colportorId;

  final TipoDeTicket tipo;
  final int montoCentavos;

  /// La foto ya comprimida y confirmada en la vista previa («¿Se lee bien el ticket?»).
  final Uint8List foto;
  final TipoDeImagen tipoDeImagen;

  /// La fecha del ticket; `null` = ahora.
  final DateTime? fecha;
  final String? numeroAutorizacion;
  final TipoDeTarjeta? tarjetaTipo;
  final String? tarjetaMarca;

  /// El cobro con tarjeta al que pertenece el ticket: queda ligado (`cobranza.ticket_id`).
  final String? cobroId;

  @override
  List<Object?> get props => [
    ticketId,
    colportorId,
    tipo,
    montoCentavos,
    foto,
    tipoDeImagen,
    fecha,
    numeroAutorizacion,
    tarjetaTipo,
    tarjetaMarca,
    cobroId,
  ];
}

/// HU-COB-007: el colportor carga el ticket (foto y datos).
///
/// 1. Valida con las reglas del servidor (`23514`): monto mayor que cero, fecha que no sea de mañana
///    (día de Montevideo), y en el ticket de tarjeta el número de autorización y si es de crédito o
///    de débito. Los textos no pasan de 40 caracteres y la foto no pasa de 2 MiB. **No guarda nada**
///    si algo está mal: la pantalla pide completarlo antes de subir.
/// 2. Lo guarda por [TicketRepository.registrar], todo o nada: el ticket, su encolado para el sync, la
///    copia local de la foto y el ligue con el cobro. La foto sube después, sola, cuando hay red y
///    el ticket ya llegó al servidor.
///
/// Con el mismo `ticketId` es idempotente. El ticket nace **pendiente** y sin revisión: eso lo pone
/// el servidor.
final class RegistrarTicketUseCase implements UseCase<TicketRegistrado, RegistrarTicketParams> {
  RegistrarTicketUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final TicketRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, TicketRegistrado>> call(RegistrarTicketParams params) async {
    if (params.ticketId.trim().isEmpty || params.colportorId.trim().isEmpty) {
      return const Left(FailureTicketNoGuardado(causa: 'faltan_ids'));
    }
    if (!ReglasDeTicket.montoValido(params.montoCentavos)) {
      return const Left(FailureTicketMontoInvalido());
    }
    final ahora = _ahora().toUtc();
    final fecha = (params.fecha ?? ahora).toUtc();
    if (!ReglasDeTicket.fechaValida(fecha, ahora)) {
      return const Left(FailureTicketFechaInvalida());
    }
    final autorizacion = ReglasDeTicket.limpio(params.numeroAutorizacion);
    final marca = ReglasDeTicket.limpio(params.tarjetaMarca);
    if (!ReglasDeTicket.textoValido(autorizacion) || !ReglasDeTicket.textoValido(marca)) {
      return const Left(FailureTicketTextoLargo());
    }
    if (ReglasDeTicket.pideAutorizacion(params.tipo) && autorizacion == null) {
      return const Left(FailureTicketSinAutorizacion());
    }
    if (ReglasDeTicket.pideTarjeta(params.tipo) && params.tarjetaTipo == null) {
      return const Left(FailureTicketSinTarjeta());
    }
    if (!ReglasDeTicket.fotoValida(params.foto.length)) {
      return const Left(FailureTicketFotoInvalida());
    }
    final cobroId = ReglasDeTicket.limpio(params.cobroId);
    if (cobroId != null && params.tipo != TipoDeTicket.cobroTarjeta) {
      return const Left(FailureTicketCobroInvalido());
    }

    return _repository.registrar(
      Ticket(
        id: params.ticketId.trim(),
        tipo: params.tipo,
        montoCentavos: params.montoCentavos,
        fecha: fecha,
        numeroAutorizacion: autorizacion,
        // Los datos de la tarjeta son solo del ticket de tarjeta (el de un depósito no los lleva).
        tarjetaTipo: params.tipo == TipoDeTicket.cobroTarjeta ? params.tarjetaTipo : null,
        tarjetaMarca: params.tipo == TipoDeTicket.cobroTarjeta ? marca : null,
        auditoria: Auditoria(
          createdAt: ahora,
          updatedAt: ahora,
          createdBy: params.colportorId.trim(),
        ),
      ),
      foto: params.foto,
      tipoDeImagen: params.tipoDeImagen,
      cobroId: cobroId,
    );
  }
}

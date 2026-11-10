import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/transaccion_local.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../tickets/domain/entities/ticket.dart';
import '../../../tickets/domain/services/puertos_de_fotos.dart';
import '../../../tickets/domain/usecases/registrar_ticket_use_case.dart';
import '../entities/deposito.dart';
import 'registrar_deposito_use_case.dart';

/// Parámetros de [RegistrarDepositoConTicketUseCase].
final class RegistrarDepositoConTicketParams extends Equatable {
  const RegistrarDepositoConTicketParams({
    required this.depositoId,
    required this.ticketId,
    required this.colportorId,
    required this.montoCentavos,
    required this.destino,
    required this.concepto,
    this.fecha,
    this.campaniaId,
    this.foto,
    this.tipoDeImagen = TipoDeImagen.jpeg,
    this.referencia,
  });

  /// El id del depósito y el de su ticket: los genera la pantalla al registrar y los repite en los
  /// reintentos con los mismos datos, así un doble toque o un «Reintentar» no registran dos veces.
  final String depositoId;
  final String ticketId;

  /// Quién deposita: el `created_by` de las filas.
  final String colportorId;

  final int montoCentavos;
  final DestinoDeDeposito destino;
  final ConceptoDeDeposito concepto;

  /// Cuándo depositó; `null` = ahora. Es también la fecha del ticket.
  final DateTime? fecha;

  /// La campaña a la que paga; obligatoria con [ConceptoDeDeposito.alquiler].
  final String? campaniaId;

  /// La foto del ticket del banco, ya comprimida; obligatoria con banco u oficina y ausente en un
  /// retiro por el coordinador.
  final Uint8List? foto;
  final TipoDeImagen tipoDeImagen;

  /// El número de operación del ticket (la «referencia» de HU-CTA-004), opcional.
  final String? referencia;

  @override
  List<Object?> get props => [
    depositoId,
    ticketId,
    colportorId,
    montoCentavos,
    destino,
    concepto,
    fecha,
    campaniaId,
    foto,
    tipoDeImagen,
    referencia,
  ];
}

/// HU-CTA-004 con la decisión «Paso ticket» (Cristian, 23/10): el depósito en el banco o en la oficina
/// **se registra al cargar su ticket, en un solo paso**; el retiro por el coordinador no lleva ticket.
///
/// 1. Valida el depósito con las reglas del servidor (`RegistrarDepositoUseCase.validar`) y que la
///    foto venga cuando el destino lleva ticket (y no venga en un retiro). **No guarda nada** si algo
///    está mal.
/// 2. En una sola [TransaccionLocal]: registra el ticket (tipo depósito, el mismo monto y la misma
///    fecha, con su foto en la cola de subida) y después el depósito que lo nombra. Si el depósito no
///    entra, el ticket tampoco queda: nunca un ticket suelto ni un depósito sin su ticket. El ticket
///    se encola antes, así sube antes que el depósito que lo nombra. Si se revierte, la copia de la
///    foto que ya se había escrito en el teléfono se borra: no queda un archivo sin su ticket.
///
/// Con los mismos ids es idempotente: devuelve el depósito que ya estaba (`yaEstaba`). El depósito
/// nace «por validar» (decisión «Acredita V1»).
final class RegistrarDepositoConTicketUseCase
    implements UseCase<DepositoRegistrado, RegistrarDepositoConTicketParams> {
  RegistrarDepositoConTicketUseCase({
    required this._transaccion,
    required this._registrarTicket,
    required this._registrarDeposito,
    required this._almacen,
    DateTime Function()? ahora,
  }) : _ahora = ahora ?? DateTime.now;

  final TransaccionLocal _transaccion;
  final RegistrarTicketUseCase _registrarTicket;
  final RegistrarDepositoUseCase _registrarDeposito;

  /// Donde quedó la copia de la foto: si la transacción se revierte, se borra.
  final AlmacenDeFotosDeTicket _almacen;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, DepositoRegistrado>> call(RegistrarDepositoConTicketParams params) async {
    final llevaTicket = params.destino.llevaTicket;
    final ticketId = params.ticketId.trim();
    if (llevaTicket && ticketId.isEmpty) {
      return const Left(FailureDepositoNoGuardado(causa: 'faltan_ids'));
    }
    final foto = params.foto;
    if (llevaTicket && (foto == null || foto.isEmpty)) {
      return const Left(FailureDepositoSinTicket());
    }
    if (!llevaTicket && foto != null) return const Left(FailureDepositoRetiroConTicket());

    // La misma fecha para el ticket y el depósito, tomada una sola vez.
    final ahora = _ahora().toUtc();
    final fecha = (params.fecha ?? ahora).toUtc();
    final deposito = RegistrarDepositoParams(
      depositoId: params.depositoId,
      colportorId: params.colportorId,
      montoCentavos: params.montoCentavos,
      destino: params.destino,
      concepto: params.concepto,
      fecha: fecha,
      campaniaId: params.campaniaId,
      ticketId: llevaTicket ? ticketId : null,
    );
    final invalido = RegistrarDepositoUseCase.validar(deposito, ahora);
    if (invalido != null) return Left(invalido);

    // La copia de la foto que escribió este intento (no la de un reintento que ya estaba).
    String? fotoEscrita;
    try {
      final registrado = await _transaccion.correr(() async {
        if (llevaTicket) {
          final ticket = await _registrarTicket(
            RegistrarTicketParams(
              ticketId: ticketId,
              colportorId: params.colportorId,
              tipo: TipoDeTicket.deposito,
              montoCentavos: params.montoCentavos,
              foto: foto!,
              tipoDeImagen: params.tipoDeImagen,
              fecha: fecha,
              numeroAutorizacion: params.referencia,
            ),
          );
          switch (ticket) {
            case Left(value: final falla):
              throw _Cancelado(falla);
            case Right(value: final ok) when !ok.yaEstaba:
              fotoEscrita = ok.foto.rutaLocal;
            case Right():
              break;
          }
        }
        final resultado = await _registrarDeposito(deposito);
        return resultado.fold((falla) => throw _Cancelado(falla), (ok) => ok);
      });
      return Right(registrado);
    } on _Cancelado catch (c) {
      await _borrarLaFoto(fotoEscrita);
      return Left(_comoFallaDelDeposito(c.falla));
    } on Object catch (e) {
      await _borrarLaFoto(fotoEscrita);
      return Left(FailureDepositoNoGuardado(causa: e.runtimeType.toString()));
    }
  }

  /// Borra la copia de la foto de un ticket que se revirtió. Si no se puede, queda: no cambia la
  /// respuesta (el depósito igual no se registró).
  Future<void> _borrarLaFoto(String? ruta) async {
    if (ruta == null) return;
    try {
      await _almacen.borrar(ruta);
    } on Object {
      // Un archivo que sobra no es motivo para decir otra cosa.
    }
  }

  /// Las fallas del ticket que tienen su par en el depósito se dicen como del depósito: la pantalla
  /// habla de «el depósito», no de «el ticket». Las propias del ticket (la foto, el largo del número)
  /// siguen como están.
  static Failure _comoFallaDelDeposito(Failure falla) => switch (falla) {
    FailureTicketNoGuardado(:final causa) => FailureDepositoNoGuardado(causa: causa),
    FailureTicketMontoInvalido() => const FailureDepositoMontoInvalido(),
    FailureTicketFechaInvalida() => const FailureDepositoFechaInvalida(),
    _ => falla,
  };
}

/// Corta la transacción con la falla de uno de los dos registros: se revierte todo lo escrito.
final class _Cancelado implements Exception {
  const _Cancelado(this.falla);
  final Failure falla;
}

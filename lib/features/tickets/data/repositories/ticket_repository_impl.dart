import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/repositories/ticket_repository.dart';
import '../../domain/services/puertos_de_fotos.dart';
import '../datasources/ticket_local_data_source_drift.dart';

/// Implementación de [TicketRepository] sobre [TicketLocalDataSourceDrift] y el [AlmacenDeFotosDeTicket].
///
/// - El archivo de la foto se guarda **antes** de la transacción de la DB; si la transacción falla, el
///   archivo se borra para no dejar uno huérfano. Si el ticket ya estaba (reintento), no se pisa.
/// - Traduce el rechazo de la persistencia a su `Failure` y cualquier otra excepción a uno genérico;
///   nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni el monto, ni la autorización, ni la
///   ruta del archivo (convenciones §7.5).
final class TicketRepositoryImpl implements TicketRepository {
  TicketRepositoryImpl(this._local, this._almacen, {AppLogger? logger, DateTime Function()? ahora})
    : _log = logger ?? AppLogger.instance,
      _ahora = ahora ?? DateTime.now;

  final TicketLocalDataSourceDrift _local;
  final AlmacenDeFotosDeTicket _almacen;
  final AppLogger _log;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, TicketRegistrado>> registrar(
    Ticket ticket, {
    required Uint8List foto,
    required TipoDeImagen tipoDeImagen,
    String? cobroId,
  }) async {
    String? ruta;
    try {
      ruta = await _almacen.guardar(ticket.id, tipoDeImagen, foto);
      final registrado = await _local.registrar(
        ticket,
        FotoLocalDeTicket(
          ticketId: ticket.id,
          tipoDeImagen: tipoDeImagen,
          bytes: foto.length,
          estado: EstadoDeSubida.pendiente,
          creadaEn: ticket.auditoria.createdAt,
          rutaLocal: ruta,
        ),
        cobroId: cobroId,
      );
      if (registrado.yaEstaba && registrado.foto.rutaLocal != ruta) {
        // Un reintento con el mismo id: la copia que ya estaba manda y la recién escrita sobra (salvo
        // que sea el mismo archivo).
        await _borrarSinFallar(ruta);
      }
      return Right(registrado);
    } on TicketCobroInvalidoException {
      await _borrarSinFallar(ruta);
      _log.info(LogModulo.db, 'TICKET_ALTA_RECHAZADO', 'cobro inválido', {
        'ticket_id': ticket.id,
        'motivo': 'cobro_invalido',
      });
      return const Left(FailureTicketCobroInvalido());
    } on Object catch (e, st) {
      await _borrarSinFallar(ruta);
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros. Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'TICKET_ALTA_FAIL',
        'falló el registro de un ticket',
        {'ticket_id': ticket.id, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureTicketNoGuardado(causa: tipo));
    }
  }

  @override
  Future<Either<Failure, List<FotoPorSubir>>> fotosPorSubir() => _leer(
    'TICKET_LECTURA_FAIL',
    () async => [
      for (final t in await _local.fotosPorSubir()) FotoPorSubir(ticket: t.ticket, foto: t.foto),
    ],
  );

  @override
  Future<Either<Failure, Uint8List?>> bytesDeLaFoto(String ticketId) =>
      _leer('TICKET_FOTO_LECTURA_FAIL', () async {
        final ruta = await _local.rutaLocalDe(ticketId);
        return ruta == null ? null : _almacen.leer(ruta);
      });

  @override
  Future<Either<Failure, Ticket>> marcarFotoSubida(String ticketId, String ruta) async {
    try {
      return Right(await _local.marcarFotoSubida(ticketId, ruta, _ahora()));
    } on TicketInexistenteException {
      return const Left(FailureTicketNoEncontrado());
    } on Object catch (e, st) {
      return Left(_falloDeEscritura('TICKET_FOTO_SUBIDA_FAIL', ticketId, e, st));
    }
  }

  @override
  Future<Either<Failure, Unit>> anotarIntentoFallido(
    String ticketId, {
    required String codigo,
    required bool definitivo,
  }) async {
    try {
      await _local.anotarIntentoFallido(ticketId, codigo: codigo, definitivo: definitivo);
      return const Right(unit);
    } on TicketInexistenteException {
      return const Left(FailureTicketNoEncontrado());
    } on Object catch (e, st) {
      return Left(_falloDeEscritura('TICKET_INTENTO_FAIL', ticketId, e, st));
    }
  }

  @override
  Future<Either<Failure, Unit>> borrarCopiaLocal(String ticketId) async {
    try {
      final ruta = await _local.soltarCopiaLocal(ticketId);
      // La fila ya dice «sin copia»; si el archivo no se puede borrar, queda suelto pero nadie lo
      // apunta, y la próxima vez que se guarde una copia del ticket se pisa.
      if (ruta != null) await _borrarSinFallar(ruta);
      return const Right(unit);
    } on TicketInexistenteException {
      return const Left(FailureTicketNoEncontrado());
    } on TicketCopiaSinSubirException {
      return const Left(FailureTicketCopiaSinSubir());
    } on Object catch (e, st) {
      return Left(_falloDeEscritura('TICKET_BORRAR_COPIA_FAIL', ticketId, e, st));
    }
  }

  @override
  Stream<int> cantidadDeFotosPorSubir() => _local.cantidadDeFotosPorSubir();

  @override
  Stream<Set<String>> cobrosConTicketPendiente() => _local.cobrosConTicketPendiente();

  Future<Either<Failure, T>> _leer<T>(String operacion, Future<T> Function() lectura) async {
    try {
      return Right(await lectura());
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        operacion,
        'falló la lectura de los tickets',
        {'tipo': e.runtimeType.toString()},
        null,
        st,
      );
      return const Left(FailureTicketNoDisponible());
    }
  }

  Failure _falloDeEscritura(String operacion, String ticketId, Object e, StackTrace st) {
    final tipo = e.runtimeType.toString();
    _log.error(
      LogModulo.db,
      operacion,
      'falló la escritura de un ticket',
      {'ticket_id': ticketId, 'tipo': tipo},
      null,
      st,
    );
    return FailureTicketNoGuardado(causa: tipo);
  }

  Future<void> _borrarSinFallar(String? ruta) async {
    if (ruta == null) return;
    try {
      await _almacen.borrar(ruta);
    } on Object {
      // Un archivo suelto no tumba el flujo.
    }
  }
}

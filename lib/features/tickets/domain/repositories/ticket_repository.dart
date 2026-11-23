import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../entities/ticket.dart';

/// Un ticket cuya foto falta subir, con su copia local.
final class FotoPorSubir extends Equatable {
  const FotoPorSubir({required this.ticket, required this.foto});

  final Ticket ticket;
  final FotoLocalDeTicket foto;

  @override
  List<Object?> get props => [ticket, foto];
}

/// Persistencia de los tickets del colportor y de la copia local de sus fotos (HU-COB-007, #426).
///
/// Cada escritura es **todo o nada**, en una transacción local: el ticket, su encolado para el sync
/// (que sube la fila sin la foto) y la fila de la copia local.
abstract interface class TicketRepository {
  /// Guarda [ticket] con su [foto] ya comprimida, lo encola para el sync y, si viene [cobroId], liga
  /// ese cobro al ticket (`cobranza.ticket_id`) en la misma transacción.
  ///
  /// - Con el mismo `id` es idempotente: no escribe nada y devuelve lo que estaba (`yaEstaba`).
  /// - Un [cobroId] que no existe, está anulado o ya tiene otro ticket es [FailureTicketCobroInvalido].
  ///   Cualquier otra falla es [FailureTicketNoGuardado].
  Future<Either<Failure, TicketRegistrado>> registrar(
    Ticket ticket, {
    required Uint8List foto,
    required TipoDeImagen tipoDeImagen,
    String? cobroId,
  });

  /// Los tickets cuya foto falta subir y que se pueden subir ya: la fila del ticket llegó al servidor
  /// (`sync_version` mayor que cero) y la copia local sigue ahí. El más viejo primero.
  Future<Either<Failure, List<FotoPorSubir>>> fotosPorSubir();

  /// Cuántas fotos hay para subir ya (las de [fotosPorSubir]), cada vez que cambia. La cola de subida
  /// la escucha: cuando el motor termina de subir la fila de un ticket, su foto pasa a poder subirse.
  Stream<int> cantidadDeFotosPorSubir();

  /// Los bytes de la copia local de la foto de [ticketId]; `null` si ya no está.
  Future<Either<Failure, Uint8List?>> bytesDeLaFoto(String ticketId);

  /// La foto de [ticketId] quedó en el bucket en [ruta]: la guarda en `ticket.url_cloud`, encola el
  /// `update` (de un ticket subido lo único que se completa es la foto, una vez) y marca la subida
  /// como hecha. Idempotente.
  Future<Either<Failure, Ticket>> marcarFotoSubida(String ticketId, String ruta);

  /// Anota que un intento de subir la foto de [ticketId] falló con [codigo]. Con [definitivo] la
  /// subida queda rechazada y no se reintenta; si no, sigue pendiente.
  Future<Either<Failure, Unit>> anotarIntentoFallido(
    String ticketId, {
    required String codigo,
    required bool definitivo,
  });

  /// Borra la copia local de la foto (supuesto S41). La nube queda intacta. Solo si la foto ya subió:
  /// si no, [FailureTicketCopiaSinSubir] (borrarla perdería el ticket).
  Future<Either<Failure, Unit>> borrarCopiaLocal(String ticketId);

  /// El ticket [ticketId] con su copia local, ahora y cada vez que cambia (la fila llegó al servidor,
  /// la foto subió, falló un intento, se borró la copia). `null` si no existe. La pantalla de la
  /// vista 29 C lo mira para saber si está «subiendo», «subido», «en cola» o con error.
  Stream<TicketRegistrado?> observarTicket(String ticketId);

  /// Los ids de los cobros cuyo ticket todavía no subió su foto: el cobro con «ticket pendiente»
  /// (HU-COB-007, «Sin red»). Se calcula de los tickets, no es una columna.
  Stream<Set<String>> cobrosConTicketPendiente();
}

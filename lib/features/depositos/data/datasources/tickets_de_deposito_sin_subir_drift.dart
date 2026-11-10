import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../tickets/data/models/ticket_model.dart';
import '../../../tickets/domain/entities/ticket.dart';

/// Los tickets de depósito cuya foto no pudo subir (vista 38A-08, decisión «Ticket dep.» del 10/11).
///
/// Cuenta los depósitos vivos con ticket cuya foto sigue **pendiente** después de al menos un intento
/// fallido: el depósito ya quedó registrado y la cola de fotos (#426) la reintenta sola, pero el
/// colportor tiene que saber que la foto todavía no llegó. Una foto que espera su primer intento (sin
/// red, o la fila todavía no subió) no cuenta: eso no es una falla.
final class TicketsDeDepositoSinSubirDrift {
  const TicketsDeDepositoSinSubirDrift(this._db);

  final AppDatabase _db;

  /// Cuántos hay, cada vez que cambia.
  Stream<int> observar() {
    final depositos = _db.depositos;
    final fotos = _db.ticketFotosLocales;
    final cuantos = fotos.ticketId.count();
    final consulta = _db.selectOnly(depositos)
      ..join([innerJoin(fotos, fotos.ticketId.equalsExp(depositos.ticketId))])
      ..addColumns([cuantos])
      ..where(
        depositos.deletedAt.isNull() &
            fotos.estado.equals(TicketModel.codigoDeLaSubida(EstadoDeSubida.pendiente)) &
            fotos.intentos.isBiggerThanValue(0),
      );
    return consulta.watchSingle().map((fila) => fila.read(cuantos) ?? 0).distinct();
  }
}

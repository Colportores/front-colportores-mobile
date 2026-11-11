import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../tickets/data/models/ticket_model.dart';
import '../../../tickets/domain/entities/ticket.dart';

/// Los tickets de depósito cuya foto no pudo subir (vista 38A-08, decisión «Ticket dep.» del 10/11), y
/// aparte los que ya no se pueden reintentar ([observarRechazados]).
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

  /// Las fechas de los depósitos cuya foto el servidor **rechazó para siempre** (más de 2 MiB, un tipo
  /// que no acepta, la copia local que ya no está): la cola no la reintenta y el coordinador no la ve
  /// (decisión P1 del 10/11 sobre 38A-08). La más vieja primero. Un depósito que el coordinador ya
  /// validó o rechazó no cuenta: ya lo revisó. El motivo técnico (`ultimo_error`) no se lee.
  Stream<List<DateTime>> observarRechazados() {
    final depositos = _db.depositos;
    final fotos = _db.ticketFotosLocales;
    final consulta =
        _db.select(depositos).join([innerJoin(fotos, fotos.ticketId.equalsExp(depositos.ticketId))])
          ..where(
            depositos.deletedAt.isNull() &
                depositos.validadoEn.isNull() &
                depositos.rechazadoEn.isNull() &
                fotos.estado.equals(TicketModel.codigoDeLaSubida(EstadoDeSubida.rechazada)),
          )
          ..orderBy([OrderingTerm.asc(depositos.fecha), OrderingTerm.asc(depositos.id)]);
    return consulta
        .watch()
        .map((filas) => [for (final f in filas) f.readTable(depositos).fecha])
        .distinct(_mismasFechas);
  }

  static bool _mismasFechas(List<DateTime> a, List<DateTime> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

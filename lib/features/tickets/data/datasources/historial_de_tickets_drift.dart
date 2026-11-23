import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../datos/drift_sync_meta.dart';
import '../../../depositos/data/datasources/deposito_local_data_source_drift.dart';
import '../../domain/entities/item_del_historial.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/repositories/historial_de_tickets_repository.dart';
import 'ticket_local_data_source_drift.dart';

/// Lee «Mis tickets» (vista 38B, HU-COB-009) de las tablas `deposito`, `ticket` y `ticket_foto_local`
/// de la DB cifrada, y de `sync_meta` la última bajada del servidor.
///
/// Una fila por **depósito vivo** (con su ticket, si lo lleva; el retiro por el coordinador no lo
/// lleva) y una por cada **ticket que ningún depósito nombra** (el de un cobro con tarjeta). La más
/// nueva primero; con la misma fecha, la que se cargó después. Todo sale del teléfono: sin conexión se
/// ve igual, con los estados de la última bajada.
final class HistorialDeTicketsDrift implements HistorialDeTicketsRepository {
  const HistorialDeTicketsDrift(this._db);

  final AppDatabase _db;

  Set<ResultSetImplementation<dynamic, dynamic>> get _tablas => {
    _db.depositos,
    _db.tickets,
    _db.ticketFotosLocales,
    _db.syncMetas,
  };

  @override
  Stream<HistorialDeTickets> observar() => _db
      .customSelect('SELECT 1 AS cambio_del_historial_de_tickets', readsFrom: _tablas)
      .watch()
      .asyncMap((_) => leer());

  /// El historial de ahora.
  Future<HistorialDeTickets> leer() async {
    final depositos = _db.depositos;
    final tickets = _db.tickets;
    final fotos = _db.ticketFotosLocales;

    final deDepositos = await (_db.select(depositos)..where((d) => d.deletedAt.isNull())).join([
      leftOuterJoin(tickets, tickets.id.equalsExp(depositos.ticketId) & tickets.deletedAt.isNull()),
      leftOuterJoin(fotos, fotos.ticketId.equalsExp(depositos.ticketId)),
    ]).get();

    // Los tickets que ningún depósito (vivo o de baja) nombra.
    final nombrados = _db.selectOnly(depositos)
      ..addColumns([depositos.ticketId])
      ..where(depositos.ticketId.isNotNull());
    final sueltos =
        await (_db.select(tickets)
              ..where((t) => t.deletedAt.isNull() & t.id.isNotInQuery(nombrados)))
            .join([leftOuterJoin(fotos, fotos.ticketId.equalsExp(tickets.id))])
            .get();

    final items = <ItemDelHistorial>[
      for (final fila in deDepositos)
        ItemDelHistorial.deDeposito(
          DepositoLocalDataSourceDrift.aDeposito(fila.readTable(depositos)),
          ticket: _ticket(fila.readTableOrNull(tickets)),
          foto: _foto(fila.readTableOrNull(fotos)),
        ),
      for (final fila in sueltos)
        ItemDelHistorial.deTicket(
          TicketLocalDataSourceDrift.aTicket(fila.readTable(tickets)),
          foto: _foto(fila.readTableOrNull(fotos)),
        ),
    ];
    // La más nueva primero; con la misma fecha, el id más alto (los ids son UUID v7: crecen con el tiempo).
    items.sort((a, b) {
      final porFecha = b.fecha.compareTo(a.fecha);
      return porFecha != 0 ? porFecha : b.id.compareTo(a.id);
    });
    final bajadoEn = (await DriftSyncMeta(_db).read()).lastPullAt;
    return HistorialDeTickets(items: items, bajadoEn: bajadoEn);
  }

  static Ticket? _ticket(TicketFila? fila) =>
      fila == null ? null : TicketLocalDataSourceDrift.aTicket(fila);

  static FotoLocalDeTicket? _foto(TicketFotoLocalFila? fila) =>
      fila == null ? null : TicketLocalDataSourceDrift.aFoto(fila);
}

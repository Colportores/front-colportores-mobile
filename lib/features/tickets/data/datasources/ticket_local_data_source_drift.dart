import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import '../../../cobranzas/data/models/cobranza_model.dart';
import '../../../cobranzas/domain/entities/cobranza.dart';
import '../../../mapa/data/datasources/audit_log_table.dart';
import '../../domain/entities/ticket.dart';
import '../models/ticket_model.dart';

/// La persistencia rechazó el ticket: el repositorio la traduce a un `Failure`.
sealed class TicketRechazadoException implements Exception {
  const TicketRechazadoException();
}

/// El cobro al que se quiere ligar el ticket no existe, está dado de baja, no es con tarjeta o ya
/// tiene otro ticket.
final class TicketCobroInvalidoException extends TicketRechazadoException {
  const TicketCobroInvalidoException();

  @override
  String toString() => 'TicketCobroInvalidoException';
}

/// No hay ticket con ese id.
final class TicketInexistenteException extends TicketRechazadoException {
  const TicketInexistenteException();

  @override
  String toString() => 'TicketInexistenteException';
}

/// Se quiso borrar la copia local de una foto que todavía no subió.
final class TicketCopiaSinSubirException extends TicketRechazadoException {
  const TicketCopiaSinSubirException();

  @override
  String toString() => 'TicketCopiaSinSubirException';
}

/// Un ticket con su copia local.
typedef TicketConFoto = ({Ticket ticket, FotoLocalDeTicket foto});

/// Lee y escribe los tickets en las tablas `ticket` y `ticket_foto_local` de la DB cifrada.
///
/// Cada escritura es **una transacción de Drift** (contrato-sync-engine §3: [EncoladorSync] se llama
/// adentro, así que si falla se revierte todo): el ticket, su encolado, la copia local, el ligue con el
/// cobro y la fila del `audit_log` local. El archivo de la foto lo guarda el repositorio antes.
final class TicketLocalDataSourceDrift {
  /// [_encolador] se pasa como `encolador:`.
  TicketLocalDataSourceDrift(this._db, {required this._encolador});

  final AppDatabase _db;
  final EncoladorSync _encolador;

  /// Ver [TicketRepository.registrar]. Lanza una [TicketRechazadoException] si no entra.
  Future<TicketRegistrado> registrar(
    Ticket ticket,
    FotoLocalDeTicket foto, {
    String? cobroId,
  }) => _db.transaction(() async {
    final existente = await _porId(ticket.id);
    if (existente != null) {
      // Un segundo toque o un reintento con el mismo id: no se escribe nada y la respuesta dice lo
      // mismo que la primera.
      return TicketRegistrado(ticket: existente.ticket, foto: existente.foto, yaEstaba: true);
    }

    // El orden importa: el ticket se encola antes que el cobro que lo nombra, porque el servidor
    // rechaza con `23503` un cobro cuyo ticket todavía no existe.
    await _db.into(_db.tickets).insert(_aFilaDeTicket(ticket));
    await _encolador.encolar('ticket', OperacionSync.insert, TicketModel.toJson(ticket));
    await _db.into(_db.ticketFotosLocales).insert(_aFilaDeFoto(foto));
    if (cobroId != null) await _ligarAlCobro(cobroId, ticket);
    // «Audit log local» (HU-COB-007): una fila por ticket, solo con su id.
    await _db
        .into(_db.auditLogLocal)
        .insert(
          AuditLogLocalCompanion.insert(
            evento: EventoAuditoriaLocal.ticketRegistrado,
            uuid: ticket.id,
            creadoEn: ticket.auditoria.createdAt,
          ),
        );
    return TicketRegistrado(ticket: ticket, foto: foto);
  });

  /// Liga el cobro con tarjeta al ticket (`cobranza.ticket_id`) y encola el `update` con la fila
  /// entera. Un cobro que ya tiene ese ticket no se toca. Un cobro cuyo ticket anterior el coordinador
  /// **rechazó** se liga al nuevo («corregir un ticket es rechazarlo y subir uno nuevo»); si el anterior
  /// no está rechazado, el cobro conserva el suyo.
  Future<void> _ligarAlCobro(String cobroId, Ticket ticket) async {
    final fila = await (_db.select(
      _db.cobranzas,
    )..where((c) => c.id.equals(cobroId))).getSingleOrNull();
    if (fila == null ||
        fila.deletedAt != null ||
        fila.medio != CobranzaModel.codigoDelMedio(MedioCobranza.tarjeta)) {
      throw const TicketCobroInvalidoException();
    }
    final anterior = fila.ticketId;
    if (anterior == ticket.id) return;
    if (anterior != null) {
      final viejo = await (_db.select(
        _db.tickets,
      )..where((t) => t.id.equals(anterior))).getSingleOrNull();
      if (viejo == null || viejo.estado != TicketModel.codigoDelEstado(EstadoDeTicket.rechazado)) {
        throw const TicketCobroInvalidoException();
      }
    }
    await (_db.update(_db.cobranzas)..where((c) => c.id.equals(cobroId))).write(
      CobranzasCompanion(ticketId: Value(ticket.id), updatedAt: Value(ticket.auditoria.updatedAt)),
    );
    final actualizada = await (_db.select(
      _db.cobranzas,
    )..where((c) => c.id.equals(cobroId))).getSingle();
    await _encolador.encolar(
      'cobranza',
      OperacionSync.update,
      CobranzaModel.toJson(CobranzaLocalDataSourceDrift.aEntidad(actualizada)),
    );
  }

  /// Ver [TicketRepository.fotosPorSubir].
  Future<List<TicketConFoto>> fotosPorSubir() async => _aLista(await _consultaPorSubir().get());

  /// Ver [TicketRepository.cantidadDeFotosPorSubir].
  Stream<int> cantidadDeFotosPorSubir() =>
      _consultaPorSubir().watch().map((filas) => filas.length).distinct();

  /// Los tickets cuya foto falta subir y se puede subir: la fila ya llegó al servidor, la copia sigue
  /// ahí y la subida no fue rechazada. El más viejo primero.
  JoinedSelectStatement<HasResultSet, dynamic> _consultaPorSubir() {
    final tickets = _db.tickets;
    final fotos = _db.ticketFotosLocales;
    return _db.select(tickets).join([innerJoin(fotos, fotos.ticketId.equalsExp(tickets.id))])
      ..where(
        tickets.urlCloud.isNull() &
            tickets.deletedAt.isNull() &
            tickets.syncVersion.isBiggerThanValue(0) &
            fotos.estado.equals(TicketModel.codigoDeLaSubida(EstadoDeSubida.pendiente)) &
            fotos.rutaLocal.isNotNull(),
      )
      ..orderBy([OrderingTerm.asc(tickets.createdAt), OrderingTerm.asc(tickets.id)]);
  }

  List<TicketConFoto> _aLista(List<TypedResult> filas) => [
    for (final f in filas)
      (
        ticket: _aTicket(f.readTable(_db.tickets)),
        foto: _aFoto(f.readTable(_db.ticketFotosLocales)),
      ),
  ];

  /// La ruta del archivo de la copia local; `null` si no hay ticket, no hay copia o se borró.
  Future<String?> rutaLocalDe(String ticketId) async {
    final fila = await (_db.select(
      _db.ticketFotosLocales,
    )..where((f) => f.ticketId.equals(ticketId))).getSingleOrNull();
    return fila?.rutaLocal;
  }

  /// Ver [TicketRepository.marcarFotoSubida]. Lanza [TicketInexistenteException] si no hay ticket.
  Future<Ticket> marcarFotoSubida(String ticketId, String ruta, DateTime ahora) => _db.transaction(
    () async {
      final actual = await _porId(ticketId);
      if (actual == null) throw const TicketInexistenteException();
      if (actual.ticket.fotoSubida) {
        // Ya estaba la ruta: se asegura que la copia diga «subida» y no se encola nada de nuevo.
        await _marcarSubida(ticketId);
        return actual.ticket;
      }
      final actualizado = actual.ticket.copyWith(
        urlCloud: ruta,
        auditoria: actual.ticket.auditoria.copyWith(updatedAt: ahora),
      );
      await (_db.update(_db.tickets)..where((t) => t.id.equals(ticketId))).write(
        TicketsCompanion(urlCloud: Value(ruta), updatedAt: Value(actualizado.auditoria.updatedAt)),
      );
      // De un ticket subido lo único que el servidor deja completar es la foto, una vez: el update
      // lleva la fila entera con los mismos datos y la ruta.
      await _encolador.encolar('ticket', OperacionSync.update, TicketModel.toJson(actualizado));
      await _marcarSubida(ticketId);
      return actualizado;
    },
  );

  Future<void> _marcarSubida(String ticketId) =>
      (_db.update(_db.ticketFotosLocales)..where((f) => f.ticketId.equals(ticketId))).write(
        TicketFotosLocalesCompanion(
          estado: Value(TicketModel.codigoDeLaSubida(EstadoDeSubida.subida)),
          ultimoError: const Value(null),
        ),
      );

  /// Ver [TicketRepository.anotarIntentoFallido].
  Future<void> anotarIntentoFallido(
    String ticketId, {
    required String codigo,
    required bool definitivo,
  }) => _db.transaction(() async {
    final fila = await (_db.select(
      _db.ticketFotosLocales,
    )..where((f) => f.ticketId.equals(ticketId))).getSingleOrNull();
    if (fila == null) throw const TicketInexistenteException();
    await (_db.update(_db.ticketFotosLocales)..where((f) => f.ticketId.equals(ticketId))).write(
      TicketFotosLocalesCompanion(
        intentos: Value(fila.intentos + 1),
        ultimoError: Value(codigo),
        estado: definitivo
            ? Value(TicketModel.codigoDeLaSubida(EstadoDeSubida.rechazada))
            : const Value.absent(),
      ),
    );
  });

  /// Ver [TicketRepository.borrarCopiaLocal]. Devuelve la ruta que había (para borrar el archivo);
  /// `null` si ya no había copia. Lanza [TicketInexistenteException] o [TicketCopiaSinSubirException].
  Future<String?> soltarCopiaLocal(String ticketId) => _db.transaction(() async {
    final fila = await (_db.select(
      _db.ticketFotosLocales,
    )..where((f) => f.ticketId.equals(ticketId))).getSingleOrNull();
    if (fila == null) throw const TicketInexistenteException();
    if (fila.estado != TicketModel.codigoDeLaSubida(EstadoDeSubida.subida)) {
      throw const TicketCopiaSinSubirException();
    }
    await (_db.update(_db.ticketFotosLocales)..where((f) => f.ticketId.equals(ticketId))).write(
      const TicketFotosLocalesCompanion(rutaLocal: Value(null)),
    );
    return fila.rutaLocal;
  });

  /// Ver [TicketRepository.cobrosConTicketPendiente]. El cobro está «con ticket pendiente» mientras la
  /// foto de su ticket **de este teléfono** no esté en la nube (copia local sin subir o rechazada). Se
  /// mide con la subida local y no con `url_cloud`: a los 4 meses el servidor suelta la ruta y esos
  /// cobros no pasan a estar «pendientes».
  Stream<Set<String>> cobrosConTicketPendiente() {
    final cobros = _db.cobranzas;
    final tickets = _db.tickets;
    final fotos = _db.ticketFotosLocales;
    final consulta =
        _db.select(cobros).join([
          innerJoin(tickets, tickets.id.equalsExp(cobros.ticketId)),
          innerJoin(fotos, fotos.ticketId.equalsExp(tickets.id)),
        ])..where(
          cobros.deletedAt.isNull() &
              tickets.deletedAt.isNull() &
              fotos.estado.equals(TicketModel.codigoDeLaSubida(EstadoDeSubida.subida)).not(),
        );
    return consulta
        .watch()
        .map((filas) => {for (final f in filas) f.readTable(cobros).id})
        .distinct(_mismosIds);
  }

  static bool _mismosIds(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  Future<TicketConFoto?> _porId(String id) async {
    final t = await (_db.select(_db.tickets)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (t == null) return null;
    final f = await (_db.select(
      _db.ticketFotosLocales,
    )..where((f) => f.ticketId.equals(id))).getSingleOrNull();
    if (f == null) return null;
    return (ticket: _aTicket(t), foto: _aFoto(f));
  }

  static Ticket _aTicket(TicketFila fila) => Ticket(
    id: fila.id,
    tipo: TicketModel.tipoDesdeCodigo(fila.tipo),
    // Un ticket de antes de la migración 0113 puede venir sin monto o sin fecha: se lee igual.
    montoCentavos: fila.monto ?? 0,
    fecha: fila.fecha ?? fila.createdAt,
    numeroAutorizacion: fila.numeroAutorizacion,
    tarjetaTipo: TicketModel.tarjetaDesdeCodigo(fila.tarjetaTipo),
    tarjetaMarca: fila.tarjetaMarca,
    urlCloud: fila.urlCloud,
    estado: TicketModel.estadoDesdeCodigo(fila.estado),
    motivoRechazo: fila.motivoRechazo,
    campaniaValidadoraId: fila.campaniaValidadoraId,
    usuarioId: fila.usuarioId,
    subidoEn: fila.subidoEn,
    revisadoPor: fila.revisadoPor,
    revisadoEn: fila.revisadoEn,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static FotoLocalDeTicket _aFoto(TicketFotoLocalFila fila) => FotoLocalDeTicket(
    ticketId: fila.ticketId,
    tipoDeImagen: TipoDeImagen.desdeMime(fila.tipoDeImagen) ?? TipoDeImagen.jpeg,
    bytes: fila.bytes,
    estado: TicketModel.subidaDesdeCodigo(fila.estado),
    creadaEn: fila.creadaEn,
    rutaLocal: fila.rutaLocal,
    intentos: fila.intentos,
    ultimoError: fila.ultimoError,
  );

  static TicketsCompanion _aFilaDeTicket(Ticket t) => TicketsCompanion.insert(
    id: t.id,
    tipo: TicketModel.codigoDelTipo(t.tipo),
    monto: Value(t.montoCentavos),
    fecha: Value(t.fecha),
    numeroAutorizacion: Value(t.numeroAutorizacion),
    tarjetaTipo: Value(
      t.tarjetaTipo == null ? null : TicketModel.codigoDeLaTarjeta(t.tarjetaTipo!),
    ),
    tarjetaMarca: Value(t.tarjetaMarca),
    urlCloud: Value(t.urlCloud),
    createdAt: t.auditoria.createdAt,
    updatedAt: t.auditoria.updatedAt,
    createdBy: Value(t.auditoria.createdBy),
    deletedAt: Value(t.auditoria.deletedAt),
    syncVersion: Value(t.auditoria.syncVersion),
  );

  static TicketFotosLocalesCompanion _aFilaDeFoto(FotoLocalDeTicket f) =>
      TicketFotosLocalesCompanion.insert(
        ticketId: f.ticketId,
        tipoDeImagen: f.tipoDeImagen.mime,
        bytes: f.bytes,
        estado: Value(TicketModel.codigoDeLaSubida(f.estado)),
        rutaLocal: Value(f.rutaLocal),
        intentos: Value(f.intentos),
        ultimoError: Value(f.ultimoError),
        creadaEn: f.creadaEn,
      );
}

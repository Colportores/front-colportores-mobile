import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../mapa/data/datasources/notas_table.dart';
import '../../../mapa/domain/services/house_status_updater.dart';
import '../../domain/entities/agenda.dart';
import '../../domain/entities/estado_agenda.dart';
import '../../domain/entities/motivo_rechazo_agenda.dart';
import '../../domain/entities/nota_de_campo.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/entities/visita.dart';
import '../models/agenda_model.dart';
import '../models/visita_model.dart';
import 'agenda_local_data_source.dart';

typedef _Motivo = MotivoRechazoAgenda;

/// [AgendaLocalDataSource] sobre las tablas `agenda`, `visita` y `nota` de la DB cifrada.
///
/// Cada operación es **una transacción de Drift** que escribe la fila, la encola para el sync
/// (contrato-sync-engine §3: [EncoladorSync] se llama adentro, así que si falla se revierte todo),
/// guarda la nota local-only y le pide a [HouseStatusUpdater] que recalcule el color de la casa
/// (R-UB08). Drift no corre dos transacciones a la vez sobre la misma DB: dos llamadas casi
/// simultáneas (un doble toque, dos acciones seguidas) se serializan y la segunda ve lo que dejó la
/// primera.
///
/// El orden de la cola importa para el servidor (`agenda.visita_id` apunta a `visita`): primero
/// el `insert` de la visita y después el `update` de la agenda que cumple.
final class AgendaLocalDataSourceDrift implements AgendaLocalDataSource {
  /// [_encolador] y [_estadoDeLasCasas] se pasan como `encolador:` y `estadoDeLasCasas:`
  /// (parámetros nombrados privados, Dart ≥ 3.10).
  AgendaLocalDataSourceDrift(this._db, {required this._encolador, required this._estadoDeLasCasas});

  final AppDatabase _db;
  final EncoladorSync _encolador;
  final HouseStatusUpdater _estadoDeLasCasas;

  @override
  Future<AgendaAgendada> agendar(Agenda agenda, {NotaDeCampo? nota}) => _db.transaction(() async {
    final existente = await _agendaPorId(agenda.id);
    if (existente != null) return (agenda: _aAgenda(existente), yaEstaba: true);

    await _exigirVinculo(agenda.espacioPersonaId);
    await _db.into(_db.agendas).insert(_aFilaAgenda(agenda));
    await _encolador.encolar(
      'agenda',
      OperacionSync.insert,
      AgendaModel.fromEntity(agenda).toJson(),
    );
    if (nota != null) await _guardarNota(nota, TipoObjetivoNota.agenda, agenda.id);
    await _recalcular(
      agenda.espacioPersonaId,
      ahora: agenda.auditoria.updatedAt,
      colportorId: agenda.colportorId,
    );
    return (agenda: agenda, yaEstaba: false);
  });

  @override
  Future<AgendaCancelada> cancelar(String agendaId, {required DateTime ahora}) =>
      _db.transaction(() async {
        final fila = await _agendaPorId(agendaId);
        if (fila == null || fila.deletedAt != null) {
          throw const AgendaRechazadaException(_Motivo.agendaInexistente);
        }
        final estado = EstadoAgenda.desdeCodigo(fila.estado);
        // Un segundo toque sobre «Cancelar» no es un error: ya está cancelada y no se vuelve a
        // escribir ni a encolar.
        if (estado == EstadoAgenda.cancelada) return (agenda: _aAgenda(fila), escribio: false);
        if (estado.estaCerrada) throw const AgendaRechazadaException(_Motivo.agendaCerrada);

        final guardada = await _escribirAgenda(
          agendaId,
          AgendasCompanion(
            estado: Value(EstadoAgenda.cancelada.codigo),
            updatedAt: Value(instanteMs(ahora)),
          ),
        );
        await _recalcular(fila.espacioPersonaId, ahora: ahora, colportorId: fila.colportorId);
        return (agenda: guardada, escribio: true);
      });

  @override
  Future<VisitaRegistrada> registrarVisita(Visita visita, {String? agendaId, NotaDeCampo? nota}) =>
      _db.transaction(() async {
        final existente = await _visitaPorId(visita.id);
        if (existente != null) return (visita: _aVisita(existente), yaEstaba: true);

        await _exigirVinculo(visita.espacioPersonaId);
        final agenda = agendaId == null ? null : await _agendaACumplir(agendaId, visita);

        await _db.into(_db.visitas).insert(_aFilaVisita(visita));
        await _encolador.encolar(
          'visita',
          OperacionSync.insert,
          VisitaModel.fromEntity(visita).toJson(),
        );
        if (agenda != null) {
          await _escribirAgenda(
            agenda.id,
            AgendasCompanion(
              estado: Value(EstadoAgenda.completada.codigo),
              visitaId: Value(visita.id),
              updatedAt: Value(visita.auditoria.updatedAt),
            ),
          );
        }
        if (nota != null) await _guardarNota(nota, TipoObjetivoNota.visita, visita.id);
        await _recalcular(
          visita.espacioPersonaId,
          ahora: visita.auditoria.updatedAt,
          colportorId: visita.colportorId,
        );
        return (visita: visita, yaEstaba: false);
      });

  @override
  Future<Agenda?> obtenerAgenda(String id) async {
    final fila = await _agendaPorId(id);
    return fila == null ? null : _aAgenda(fila);
  }

  @override
  Future<Visita?> obtenerVisita(String id) async {
    final fila = await _visitaPorId(id);
    return fila == null ? null : _aVisita(fila);
  }

  Future<AgendaFila?> _agendaPorId(String id) =>
      (_db.select(_db.agendas)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<VisitaFila?> _visitaPorId(String id) =>
      (_db.select(_db.visitas)..where((v) => v.id.equals(id))).getSingleOrNull();

  /// El vínculo persona ↔ espacio tiene que estar en el teléfono y sin baja: el servidor lo exige
  /// (`espacio_persona_id` es `NOT NULL` con FK) y la pantalla lo eligió de la casa.
  Future<void> _exigirVinculo(String espacioPersonaId) async {
    final vinculo = await (_db.select(
      _db.espacioPersonas,
    )..where((v) => v.id.equals(espacioPersonaId))).getSingleOrNull();
    if (vinculo == null || vinculo.deletedAt != null) {
      throw const AgendaRechazadaException(_Motivo.personaInexistente);
    }
  }

  /// La agenda que [visita] cumple: existe, es de la misma persona y sigue pendiente.
  Future<AgendaFila> _agendaACumplir(String agendaId, Visita visita) async {
    final fila = await _agendaPorId(agendaId);
    if (fila == null || fila.deletedAt != null) {
      throw const AgendaRechazadaException(_Motivo.agendaInexistente);
    }
    if (fila.espacioPersonaId != visita.espacioPersonaId) {
      throw const AgendaRechazadaException(_Motivo.agendaDeOtraPersona);
    }
    if (EstadoAgenda.desdeCodigo(fila.estado).estaCerrada) {
      throw const AgendaRechazadaException(_Motivo.agendaCerrada);
    }
    return fila;
  }

  /// Aplica [cambios] a la agenda [id], lee la fila resultante y encola su `update` con la fila
  /// entera.
  Future<Agenda> _escribirAgenda(String id, AgendasCompanion cambios) async {
    await (_db.update(_db.agendas)..where((a) => a.id.equals(id))).write(cambios);
    final agenda = _aAgenda((await _agendaPorId(id))!);
    await _encolador.encolar(
      'agenda',
      OperacionSync.update,
      AgendaModel.fromEntity(agenda).toJson(),
    );
    return agenda;
  }

  Future<void> _guardarNota(NotaDeCampo nota, String tipoObjetivo, String objetivoId) => _db
      .into(_db.notas)
      .insert(
        NotasCompanion.insert(
          id: nota.id,
          targetType: tipoObjetivo,
          targetId: objetivoId,
          texto: nota.texto,
          createdAt: nota.auditoria.createdAt,
          updatedAt: nota.auditoria.updatedAt,
          createdBy: Value(nota.auditoria.createdBy),
          deletedAt: Value(nota.auditoria.deletedAt),
          syncVersion: Value(nota.auditoria.syncVersion),
        ),
      );

  /// Recalcula el color de la casa a la que pertenece el vínculo [espacioPersonaId]. Si el espacio
  /// del vínculo no está en el teléfono (el pull no garantiza el orden) no hay casa que pintar: la
  /// agenda o la visita se guarda igual, porque no se pierde un registro de campo por una fila que
  /// falta.
  Future<void> _recalcular(
    String espacioPersonaId, {
    required DateTime ahora,
    required String colportorId,
  }) async {
    final consulta =
        _db.selectOnly(_db.espacioPersonas).join([
            innerJoin(_db.espacios, _db.espacios.id.equalsExp(_db.espacioPersonas.espacioId)),
          ])
          ..addColumns([_db.espacios.ubicacionId])
          ..where(_db.espacioPersonas.id.equals(espacioPersonaId));
    final fila = await consulta.getSingleOrNull();
    final ubicacionId = fila?.read(_db.espacios.ubicacionId);
    if (ubicacionId == null) return;
    await _estadoDeLasCasas.recalcular(ubicacionId, ahora: ahora, colportorId: colportorId);
  }

  static Agenda _aAgenda(AgendaFila fila) => Agenda(
    id: fila.id,
    espacioPersonaId: fila.espacioPersonaId,
    tipo: TipoAgenda.desdeCodigo(fila.tipo),
    fechaProgramada: fila.fechaProgramada,
    slotCodigo: fila.slotCodigo,
    esEstricta: fila.esEstricta,
    ubicacionAltId: fila.ubicacionAltId,
    estado: EstadoAgenda.desdeCodigo(fila.estado),
    colportorId: fila.colportorId,
    visitaId: fila.visitaId,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static Visita _aVisita(VisitaFila fila) => Visita(
    id: fila.id,
    espacioPersonaId: fila.espacioPersonaId,
    fecha: fila.fecha,
    tipoResultado: TipoResultadoVisita.desdeCodigo(fila.tipoResultado),
    colportorId: fila.colportorId,
    jornadaId: fila.jornadaId,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static AgendasCompanion _aFilaAgenda(Agenda a) => AgendasCompanion.insert(
    id: a.id,
    espacioPersonaId: a.espacioPersonaId,
    tipo: a.tipo.codigo,
    fechaProgramada: a.fechaProgramada,
    slotCodigo: Value(a.slotCodigo),
    esEstricta: Value(a.esEstricta),
    ubicacionAltId: Value(a.ubicacionAltId),
    estado: Value(a.estado.codigo),
    colportorId: a.colportorId,
    visitaId: Value(a.visitaId),
    createdAt: a.auditoria.createdAt,
    updatedAt: a.auditoria.updatedAt,
    createdBy: Value(a.auditoria.createdBy),
    deletedAt: Value(a.auditoria.deletedAt),
    syncVersion: Value(a.auditoria.syncVersion),
  );

  static VisitasCompanion _aFilaVisita(Visita v) => VisitasCompanion.insert(
    id: v.id,
    espacioPersonaId: v.espacioPersonaId,
    fecha: v.fecha,
    tipoResultado: v.tipoResultado.codigo,
    colportorId: v.colportorId,
    jornadaId: Value(v.jornadaId),
    createdAt: v.auditoria.createdAt,
    updatedAt: v.auditoria.updatedAt,
    createdBy: Value(v.auditoria.createdBy),
    deletedAt: Value(v.auditoria.deletedAt),
    syncVersion: Value(v.auditoria.syncVersion),
  );
}

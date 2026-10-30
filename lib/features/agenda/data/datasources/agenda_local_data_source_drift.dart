import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../mapa/data/datasources/audit_log_table.dart';
import '../../../mapa/data/datasources/notas_table.dart';
import '../../../mapa/domain/services/house_status_updater.dart';
import '../../domain/entities/agenda.dart';
import '../../domain/entities/cambios_de_agenda.dart';
import '../../domain/entities/detalle_de_agenda.dart';
import '../../domain/entities/estado_agenda.dart';
import '../../domain/entities/motivo_rechazo_agenda.dart';
import '../../domain/entities/nota_de_campo.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/entities/visita.dart';
import '../../domain/entities/visita_guardada.dart';
import '../models/agenda_model.dart';
import '../models/visita_model.dart';
import 'agenda_local_data_source.dart';

typedef _Motivo = MotivoRechazoAgenda;

String _uuidV7() => const Uuid().v7();

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
  AgendaLocalDataSourceDrift(
    this._db, {
    required this._encolador,
    required this._estadoDeLasCasas,
    this._generarId = _uuidV7,
  });

  final AppDatabase _db;
  final EncoladorSync _encolador;
  final HouseStatusUpdater _estadoDeLasCasas;

  /// Id de la agenda `CUMPLIDA` que se crea junto con una visita espontánea.
  final String Function() _generarId;

  @override
  Future<AgendaAgendada> agendar(Agenda agenda, {NotaDeCampo? nota}) => _db.transaction(() async {
    final existente = await _agendaPorId(agenda.id);
    if (existente != null) return (agenda: _aAgenda(existente), yaEstaba: true);

    await _exigirEspacioYVinculo(agenda.espacioId, agenda.espacioPersonaId);
    await _exigirAlternativaDeCobranza(agenda);
    await _db.into(_db.agendas).insert(_aFilaAgenda(agenda));
    await _encolador.encolar(
      'agenda',
      OperacionSync.insert,
      AgendaModel.fromEntity(agenda).toJson(),
    );
    if (nota != null) await _guardarNota(nota, TipoObjetivoNota.agenda, agenda.id);
    await _recalcular(
      agenda.espacioId,
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
        await _recalcular(fila.espacioId, ahora: ahora, colportorId: fila.colportorId);
        return (agenda: guardada, escribio: true);
      });

  @override
  Future<AgendaEditada> modificar(CambiosDeAgenda cambios, {required DateTime ahora}) =>
      _db.transaction(() async {
        final fila = await _agendaPorId(cambios.agendaId);
        if (fila == null || fila.deletedAt != null) {
          throw const AgendaRechazadaException(_Motivo.agendaInexistente);
        }
        // Solo se edita una agenda que sigue esperando su visita (HU-VIS-003): se mira DENTRO de la
        // transacción, porque entre abrir el formulario y guardar pudo cumplirse, cancelarse o
        // llegar cancelada del servidor.
        if (EstadoAgenda.desdeCodigo(fila.estado).estaCerrada) {
          throw const AgendaRechazadaException(_Motivo.agendaCerrada);
        }

        final instante = instanteMs(ahora);
        final cuando = instanteMs(cambios.fechaProgramada);
        final cambiaLaFila =
            fila.tipo != cambios.tipo.codigo ||
            fila.fechaProgramada != cuando ||
            fila.slotCodigo != cambios.slotCodigo;
        final cambiaLaNota = await _guardarNotaEditada(cambios, instante, fila.colportorId);
        if (!cambiaLaFila && !cambiaLaNota) return (agenda: _aAgenda(fila), escribio: false);

        var agenda = _aAgenda(fila);
        if (cambiaLaFila) {
          agenda = await _escribirAgenda(
            cambios.agendaId,
            AgendasCompanion(
              tipo: Value(cambios.tipo.codigo),
              fechaProgramada: Value(cuando),
              slotCodigo: Value(cambios.slotCodigo),
              updatedAt: Value(instante),
            ),
          );
          await _recalcular(fila.espacioId, ahora: ahora, colportorId: fila.colportorId);
        }
        // «Audit log local» (HU-VIS-003): una fila por modificación, solo con el id de la agenda.
        await _db
            .into(_db.auditLogLocal)
            .insert(
              AuditLogLocalCompanion.insert(
                evento: EventoAuditoriaLocal.agendaModificada,
                uuid: cambios.agendaId,
                creadoEn: instante,
              ),
            );
        return (agenda: agenda, escribio: true);
      });

  /// Deja la nota de la agenda como la pide [cambios] y devuelve si cambió algo. `nota == null`: no
  /// se toca. En blanco: se da de baja la vigente. Con texto: se cambia la vigente o se crea una con
  /// `idNota`.
  Future<bool> _guardarNotaEditada(CambiosDeAgenda cambios, DateTime instante, String autor) async {
    final pedida = cambios.nota?.trim();
    if (pedida == null) return false;
    final actual = await _notaVigente(cambios.agendaId);
    if (pedida.isEmpty) {
      if (actual == null) return false;
      await (_db.update(_db.notas)..where((n) => n.id.equals(actual.id))).write(
        NotasCompanion(deletedAt: Value(instante), updatedAt: Value(instante)),
      );
      return true;
    }
    if (actual == null) {
      await _guardarNota(
        NotaDeCampo(
          id: cambios.idNota,
          texto: pedida,
          auditoria: Auditoria(createdAt: instante, updatedAt: instante, createdBy: autor),
        ),
        TipoObjetivoNota.agenda,
        cambios.agendaId,
      );
      return true;
    }
    if (actual.texto == pedida) return false;
    await (_db.update(_db.notas)..where((n) => n.id.equals(actual.id))).write(
      NotasCompanion(texto: Value(pedida), updatedAt: Value(instante)),
    );
    return true;
  }

  /// La nota vigente (sin baja) de la agenda [agendaId]: la más antigua si por algún motivo hay más
  /// de una.
  Future<NotaFila?> _notaVigente(String agendaId) async {
    final filas =
        await (_db.select(_db.notas)
              ..where(
                (n) =>
                    n.targetType.equals(TipoObjetivoNota.agenda) &
                    n.targetId.equals(agendaId) &
                    n.deletedAt.isNull(),
              )
              ..orderBy([(n) => OrderingTerm.asc(n.createdAt), (n) => OrderingTerm.asc(n.id)])
              ..limit(1))
            .get();
    return filas.isEmpty ? null : filas.first;
  }

  @override
  Future<DetalleDeAgenda?> obtenerDetalle(String id) async {
    final fila = await _agendaPorId(id);
    if (fila == null || fila.deletedAt != null) return null;
    final nota = await _notaVigente(id);
    final visitaId = fila.visitaId;
    final visita = visitaId == null ? null : await _visitaPorId(visitaId);
    return DetalleDeAgenda(
      agenda: _aAgenda(fila),
      nota: nota?.texto,
      visita: visita == null || visita.deletedAt != null ? null : _aVisita(visita),
    );
  }

  @override
  Future<VisitaRegistrada> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  }) => _db.transaction(() async {
    final existente = await _visitaPorId(visita.id);
    if (existente != null) {
      // Un segundo toque o un reintento con los mismos ids: no se escribe nada, pero la respuesta
      // dice lo mismo que la primera (qué agenda cumplió o creó la visita), así «Deshacer» funciona
      // con cualquiera de las dos.
      final vinculadas = await (_db.select(
        _db.agendas,
      )..where((a) => a.visitaId.equals(visita.id) & a.deletedAt.isNull())).get();
      final vinculada = vinculadas.isEmpty ? null : vinculadas.first;
      // Con un reintento ya no se sabe cuál agenda se pasó la primera vez (la cita que la visita
      // cumplió dejó de estar programada), así que se lee de las filas: la agenda que creó la visita
      // nace con ella (mismo instante de alta); una cita de antes es anterior a la visita.
      final laCreoLaVisita =
          vinculada != null &&
          vinculada.createdAt == existente.createdAt &&
          vinculada.estado == EstadoAgenda.cumplida.codigo;
      final afectada = vinculada != null && !laCreoLaVisita;
      return (
        visita: _aVisita(existente),
        yaEstaba: true,
        agendaIgnorada: null,
        agendaNoCumplida: vinculada != null && vinculada.estado == EstadoAgenda.noCumplida.codigo,
        agendaCreadaId: laCreoLaVisita ? vinculada.id : null,
        agendaAfectadaId: afectada ? vinculada.id : null,
      );
    }

    await _exigirEspacioYVinculo(visita.espacioId, visita.espacioPersonaId);
    final (:agenda, :ignorada) = agendaId == null
        ? (agenda: null, ignorada: null)
        : await _agendaACumplir(agendaId, visita);

    await _db.into(_db.visitas).insert(_aFilaVisita(visita));
    await _encolador.encolar(
      'visita',
      OperacionSync.insert,
      VisitaModel.fromEntity(visita).toJson(),
    );
    // Una agenda que sirve pasa a `CUMPLIDA` con el resultado que la cumple, o a `NO_CUMPLIDA` con
    // «No contestó» (HU-VIS-005; decisión del 23/10, «No cumplida»): en los dos casos apunta a la
    // visita. Sin agenda, la visita espontánea nace con la suya, ya cumplida; salvo la de cobranza: pasar
    // a cobrar no es una entrevista que haya quedado hecha, así que queda en el historial sin agenda
    // (decisión del 25/10, «Cobranza sin cita no crea agenda»).
    final noLaCumple = agenda != null && !visita.tipoResultado.cumpleLaAgenda;
    String? agendaCreadaId;
    if (agenda == null) {
      if (visita.tipoResultado != TipoResultadoVisita.cobranza) {
        agendaCreadaId = await _crearAgendaCumplida(visita);
      }
    } else {
      await _escribirAgenda(
        agenda.id,
        AgendasCompanion(
          estado: Value((noLaCumple ? EstadoAgenda.noCumplida : EstadoAgenda.cumplida).codigo),
          visitaId: Value(visita.id),
          updatedAt: Value(visita.auditoria.updatedAt),
        ),
      );
    }
    if (nota != null) {
      // La entrevista en curso fue guardando su nota como borrador, con este mismo `id` y atada a esta
      // visita (vista 39, #450): el texto final la reemplaza. Solo ese borrador; una nota ajena con
      // el mismo `id` sigue haciendo fallar el alta, como siempre.
      await (_db.delete(_db.notas)..where(
            (n) =>
                n.id.equals(nota.id) &
                n.targetType.equals(TipoObjetivoNota.visita) &
                n.targetId.equals(visita.id),
          ))
          .go();
      await _guardarNota(nota, TipoObjetivoNota.visita, visita.id);
    }
    await _recalcular(
      visita.espacioId,
      ahora: visita.auditoria.updatedAt,
      colportorId: visita.colportorId,
    );
    return (
      visita: visita,
      yaEstaba: false,
      agendaIgnorada: ignorada,
      agendaNoCumplida: noLaCumple,
      agendaCreadaId: agendaCreadaId,
      agendaAfectadaId: agenda?.id,
    );
  });

  @override
  Future<VisitaDeshecha> deshacerVisita(
    String visitaId, {
    String? agendaCreadaId,
    String? agendaAfectadaId,
    required DateTime ahora,
  }) => _db.transaction(() async {
    final fila = await _visitaPorId(visitaId);
    if (fila == null) throw const AgendaRechazadaException(_Motivo.visitaInexistente);
    // Un segundo toque sobre «Deshacer» no es un error: ya está deshecha y no se vuelve a escribir
    // ni a encolar.
    if (fila.deletedAt != null) return (visita: _aVisita(fila), escribio: false);

    final instante = instanteMs(ahora);
    // La agenda primero: si la visita la cumplió o no la cumplió, vuelve a esperarla; si la creó ella
    // (visita espontánea), se da de baja con la visita.
    if (agendaCreadaId != null) {
      final creada = await _agendaPorId(agendaCreadaId);
      if (creada != null && creada.deletedAt == null && creada.visitaId == visitaId) {
        await _escribirAgenda(
          agendaCreadaId,
          AgendasCompanion(deletedAt: Value(instante), updatedAt: Value(instante)),
          operacion: OperacionSync.delete,
        );
      }
    } else if (agendaAfectadaId != null) {
      final afectada = await _agendaPorId(agendaAfectadaId);
      if (afectada != null && afectada.deletedAt == null && afectada.visitaId == visitaId) {
        await _escribirAgenda(
          agendaAfectadaId,
          AgendasCompanion(
            estado: Value(EstadoAgenda.programada.codigo),
            visitaId: const Value(null),
            updatedAt: Value(instante),
          ),
        );
      }
    }
    await (_db.update(_db.visitas)..where((v) => v.id.equals(visitaId))).write(
      VisitasCompanion(deletedAt: Value(instante), updatedAt: Value(instante)),
    );
    final deshecha = _aVisita((await _visitaPorId(visitaId))!);
    await _encolador.encolar(
      'visita',
      OperacionSync.delete,
      VisitaModel.fromEntity(deshecha).toJson(),
    );
    // Sus notas (locales) se van con ella.
    await (_db.update(_db.notas)..where(
          (n) =>
              n.targetType.equals(TipoObjetivoNota.visita) &
              n.targetId.equals(visitaId) &
              n.deletedAt.isNull(),
        ))
        .write(NotasCompanion(deletedAt: Value(instante), updatedAt: Value(instante)));
    await _recalcular(fila.espacioId, ahora: ahora, colportorId: fila.colportorId);
    return (visita: deshecha, escribio: true);
  });

  @override
  Future<Agenda?> agendaProgramadaDe(String espacioId) async {
    final filas =
        await (_db.select(_db.agendas)
              ..where(
                (a) =>
                    a.espacioId.equals(espacioId) &
                    a.tipo.equals(TipoAgenda.entrevista.codigo) &
                    a.estado.equals(EstadoAgenda.programada.codigo) &
                    a.deletedAt.isNull(),
              )
              ..orderBy([(a) => OrderingTerm.asc(a.fechaProgramada), (a) => OrderingTerm.asc(a.id)])
              ..limit(1))
            .get();
    return filas.isEmpty ? null : _aAgenda(filas.first);
  }

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

  /// El espacio (la casa o el depto) tiene que estar en el teléfono y sin baja: el servidor lo exige
  /// (`espacio_id` es `NOT NULL` con FK) y la pantalla lo eligió de la casa. Si hay persona
  /// ([espacioPersonaId]), su vínculo también tiene que estar, sin baja y **en ese espacio**: una
  /// persona de otra casa no se cuela en esta.
  Future<void> _exigirEspacioYVinculo(String espacioId, String? espacioPersonaId) async {
    final espacio = await (_db.select(
      _db.espacios,
    )..where((e) => e.id.equals(espacioId))).getSingleOrNull();
    if (espacio == null || espacio.deletedAt != null) {
      throw const AgendaRechazadaException(_Motivo.espacioInexistente);
    }
    if (espacioPersonaId == null) return;
    final vinculo = await (_db.select(
      _db.espacioPersonas,
    )..where((v) => v.id.equals(espacioPersonaId))).getSingleOrNull();
    if (vinculo == null || vinculo.deletedAt != null || vinculo.espacioId != espacioId) {
      throw const AgendaRechazadaException(_Motivo.personaInexistente);
    }
  }

  /// HU-VIS-006: cobrar en otra ubicación (`agenda.ubicacion_alt_id`) solo vale para una **cobranza**,
  /// de una persona que tiene esa ubicación como alternativa (HU-UBI-013) y que sigue activa. Sin
  /// `ubicacion_alt_id` no se pide nada. El orden es el de lo que la persona puede arreglar: el tipo,
  /// la persona, la baja de la ubicación y, al final, que siga siendo la de la persona.
  Future<void> _exigirAlternativaDeCobranza(Agenda agenda) async {
    final alternativaId = agenda.ubicacionAltId;
    if (alternativaId == null) return;
    if (agenda.tipo != TipoAgenda.cobranza) {
      throw const AgendaRechazadaException(_Motivo.alternativaSoloCobranza);
    }
    final vinculoId = agenda.espacioPersonaId;
    if (vinculoId == null) {
      throw const AgendaRechazadaException(_Motivo.alternativaSinPersona);
    }
    final ubicacion = await (_db.select(
      _db.ubicaciones,
    )..where((u) => u.id.equals(alternativaId))).getSingleOrNull();
    if (ubicacion == null) throw const AgendaRechazadaException(_Motivo.alternativaFaltante);
    if (ubicacion.deletedAt != null) {
      throw const AgendaRechazadaException(_Motivo.alternativaInactiva);
    }
    final vinculo = await (_db.select(
      _db.espacioPersonas,
    )..where((v) => v.id.equals(vinculoId))).getSingle();
    if (vinculo.ubicacionCobranzaAltId != alternativaId) {
      throw const AgendaRechazadaException(_Motivo.alternativaCambio);
    }
  }

  /// La agenda que [visita] cumple, o por qué no sirve: una agenda inexistente, de otra casa o de
  /// otra persona, o ya cerrada, no frena la visita (no se pierde lo que la colportora acaba de
  /// registrar), que se guarda como espontánea y deja la agenda como estaba.
  Future<({AgendaFila? agenda, MotivoAgendaIgnorada? ignorada})> _agendaACumplir(
    String agendaId,
    Visita visita,
  ) async {
    final fila = await _agendaPorId(agendaId);
    if (fila == null || fila.deletedAt != null) {
      return (agenda: null, ignorada: MotivoAgendaIgnorada.inexistente);
    }
    if (fila.espacioId != visita.espacioId) {
      return (agenda: null, ignorada: MotivoAgendaIgnorada.deOtraCasa);
    }
    // Una cita sin persona, o una visita sin persona, sirve para cualquiera de la casa; con las dos
    // personas, tienen que ser la misma.
    final personaDeLaCita = fila.espacioPersonaId;
    final personaDeLaVisita = visita.espacioPersonaId;
    if (personaDeLaCita != null &&
        personaDeLaVisita != null &&
        personaDeLaCita != personaDeLaVisita) {
      return (agenda: null, ignorada: MotivoAgendaIgnorada.deOtraPersona);
    }
    if (EstadoAgenda.desdeCodigo(fila.estado).estaCerrada) {
      return (agenda: null, ignorada: MotivoAgendaIgnorada.cerrada);
    }
    return (agenda: fila, ignorada: null);
  }

  /// La visita espontánea (sin agenda, o con una que no sirvió) nace con su agenda `CUMPLIDA`, en la
  /// misma transacción (HU-VIS-005; decisión del 23/10 sobre la regla «Agenda»): fecha de la visita,
  /// mismo espacio, misma persona (si la hay) y colportora, tipo `ENTREVISTA`, sin slot y no
  /// estricta. Se encola después de la visita, porque `agenda.visita_id` apunta a ella. Devuelve el
  /// id de la agenda creada.
  Future<String> _crearAgendaCumplida(Visita visita) async {
    final agenda = Agenda(
      id: _generarId(),
      espacioId: visita.espacioId,
      espacioPersonaId: visita.espacioPersonaId,
      tipo: TipoAgenda.entrevista,
      fechaProgramada: visita.fecha,
      estado: EstadoAgenda.cumplida,
      colportorId: visita.colportorId,
      visitaId: visita.id,
      auditoria: Auditoria(
        createdAt: visita.auditoria.createdAt,
        updatedAt: visita.auditoria.updatedAt,
        createdBy: visita.auditoria.createdBy,
      ),
    );
    await _db.into(_db.agendas).insert(_aFilaAgenda(agenda));
    await _encolador.encolar(
      'agenda',
      OperacionSync.insert,
      AgendaModel.fromEntity(agenda).toJson(),
    );
    return agenda.id;
  }

  /// Aplica [cambios] a la agenda [id], lee la fila resultante y encola su [operacion] (`update` por
  /// defecto) con la fila entera.
  Future<Agenda> _escribirAgenda(
    String id,
    AgendasCompanion cambios, {
    OperacionSync operacion = OperacionSync.update,
  }) async {
    await (_db.update(_db.agendas)..where((a) => a.id.equals(id))).write(cambios);
    final agenda = _aAgenda((await _agendaPorId(id))!);
    await _encolador.encolar('agenda', operacion, AgendaModel.fromEntity(agenda).toJson());
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

  /// Recalcula el color de la casa a la que pertenece el espacio [espacioId]. Si la ubicación del
  /// espacio no está en el teléfono no hay casa que pintar: la agenda o la visita se guarda igual,
  /// porque no se pierde un registro de campo por una fila que falta.
  Future<void> _recalcular(
    String espacioId, {
    required DateTime ahora,
    required String colportorId,
  }) async {
    final consulta = _db.selectOnly(_db.espacios)
      ..addColumns([_db.espacios.ubicacionId])
      ..where(_db.espacios.id.equals(espacioId));
    final fila = await consulta.getSingleOrNull();
    final ubicacionId = fila?.read(_db.espacios.ubicacionId);
    if (ubicacionId == null) return;
    await _estadoDeLasCasas.recalcular(ubicacionId, ahora: ahora, colportorId: colportorId);
  }

  static Agenda _aAgenda(AgendaFila fila) => Agenda(
    id: fila.id,
    espacioId: fila.espacioId,
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
    espacioId: fila.espacioId,
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
    espacioId: a.espacioId,
    espacioPersonaId: Value(a.espacioPersonaId),
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
    espacioId: v.espacioId,
    espacioPersonaId: Value(v.espacioPersonaId),
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

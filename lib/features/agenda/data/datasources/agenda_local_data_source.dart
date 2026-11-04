import '../../domain/entities/agenda.dart';
import '../../domain/entities/cambios_de_agenda.dart';
import '../../domain/entities/detalle_de_agenda.dart';
import '../../domain/entities/motivo_rechazo_agenda.dart';
import '../../domain/entities/nota_de_campo.dart';
import '../../domain/entities/visita.dart';
import '../../domain/entities/visita_guardada.dart';

/// Resultado de [AgendaLocalDataSource.agendar]: la agenda guardada y si ya estaba.
typedef AgendaAgendada = ({Agenda agenda, bool yaEstaba});

/// Resultado de [AgendaLocalDataSource.cancelar]: la agenda como quedó y si esta llamada escribió
/// (`false` si ya estaba cancelada).
typedef AgendaCancelada = ({Agenda agenda, bool escribio});

/// Resultado de [AgendaLocalDataSource.modificar]: la agenda como quedó y si esta llamada escribió
/// (`false` si ya tenía esos valores).
typedef AgendaEditada = ({Agenda agenda, bool escribio});

/// Resultado de [AgendaLocalDataSource.registrarVisita]: la visita guardada, si ya estaba, si la
/// agenda indicada no servía, por qué se guardó sin ella, si la agenda sirve pero el resultado no la
/// cumple (`agendaNoCumplida`: pasó a `NO_CUMPLIDA`) y qué agenda tocó: la que **creó** la visita
/// espontánea (`agendaCreadaId`) o la **existente** que cumplió o no cumplió (`agendaAfectadaId`).
/// Esos dos ids son lo que necesita [AgendaLocalDataSource.deshacerVisita].
typedef VisitaRegistrada = ({
  Visita visita,
  bool yaEstaba,
  MotivoAgendaIgnorada? agendaIgnorada,
  bool agendaNoCumplida,
  String? agendaCreadaId,
  String? agendaAfectadaId,
});

/// Resultado de [AgendaLocalDataSource.deshacerVisita]: la visita como quedó (dada de baja) y si esta
/// llamada escribió (`false` si ya estaba deshecha).
typedef VisitaDeshecha = ({Visita visita, bool escribio});

/// Persistencia local de las agendas y las visitas (BACK-HU-VIS-001), sobre las tablas `agenda`,
/// `visita` y `nota` de la DB cifrada. La implementa `AgendaLocalDataSourceDrift`.
///
/// Cada operación escribe **en una sola transacción**: la fila, su job de sync (`agenda` y `visita`
/// suben enteras, contrato-sync-engine §2), la nota opcional (local-only) y el recálculo de
/// `house_status` de la casa (R-UB08, ADR-003). Si algo falla —también el encolado—, no queda
/// nada.
abstract interface class AgendaLocalDataSource {
  /// Guarda [agenda] y su [nota] opcional. Si ya hay una agenda con ese `id`, no escribe nada y la
  /// devuelve con `yaEstaba: true` (un doble toque no la duplica).
  ///
  /// El vínculo persona ↔ espacio de la agenda tiene que estar en el teléfono: si no, lanza
  /// [AgendaRechazadaException].
  Future<AgendaAgendada> agendar(Agenda agenda, {NotaDeCampo? nota});

  /// Pasa la agenda [agendaId] a `CANCELADA`, en el instante [ahora]. Si ya estaba cancelada, no
  /// escribe nada. Si estaba cumplida o no existe, lanza [AgendaRechazadaException].
  Future<AgendaCancelada> cancelar(String agendaId, {required DateTime ahora});

  /// Aplica [cambios] a la agenda `PROGRAMADA` (HU-VIS-003) en una transacción: la fila (tipo, día y
  /// hora, franja), su job de sync, la nota (local-only: se crea, se cambia o se da de baja), el
  /// `audit_log` local y el color de la casa. Si nada cambia, no escribe nada (`escribio: false`).
  /// Lanza [AgendaRechazadaException] si la agenda no existe o ya no está programada.
  Future<AgendaEditada> modificar(CambiosDeAgenda cambios, {required DateTime ahora});

  /// La agenda [id] con su nota y la visita que la cerró, o `null` si no está en el teléfono o está
  /// dada de baja.
  Future<DetalleDeAgenda?> obtenerDetalle(String id);

  /// Guarda [visita] y su [nota] opcional. Con [agendaId], la agenda que la visita cumple pasa a
  /// `CUMPLIDA` y apunta a la visita, en la misma transacción. Si ya hay una visita con ese `id`,
  /// no escribe nada y la devuelve con `yaEstaba: true`.
  ///
  /// Un resultado que no cumple la agenda (`TipoResultadoVisita.cumpleLaAgenda`, hoy `NO_CONTESTO`)
  /// guarda la visita y pasa la agenda a `NO_CUMPLIDA` (apuntando a la visita), sin crear una agenda
  /// cumplida de más: `agendaNoCumplida: true`.
  ///
  /// Lanza [AgendaRechazadaException] si el espacio de la visita, o su persona (si la hay), no están
  /// en el teléfono. Si la agenda no existe, es de otra casa o de otra persona, o ya no está
  /// programada, la visita se guarda igual como espontánea, sin tocar esa agenda, y el resultado trae
  /// el motivo en `agendaIgnorada`.
  Future<VisitaRegistrada> registrarVisita(Visita visita, {String? agendaId, NotaDeCampo? nota});

  /// Deshace [visitaId] (el «Deshacer» de R·01): da de baja la visita y sus notas, vuelve a
  /// `PROGRAMADA` la agenda existente que la visita cumplió o no cumplió ([agendaAfectadaId]) o da de
  /// baja la que creó ([agendaCreadaId]), y recalcula el color de la casa, todo en una transacción.
  /// Si ya estaba deshecha, no escribe nada (`escribio: false`). Lanza [AgendaRechazadaException] si
  /// la visita no está en el teléfono.
  Future<VisitaDeshecha> deshacerVisita(
    String visitaId, {
    String? agendaCreadaId,
    String? agendaAfectadaId,
    required DateTime ahora,
  });

  /// La agenda de entrevista que sigue `PROGRAMADA` en [espacioId] (la más próxima), o `null` si no
  /// hay ninguna. La visita que se registra en esa casa es la que viene a cumplirla.
  Future<Agenda?> agendaProgramadaDe(String espacioId);

  /// La agenda [id], o `null` si no está en el teléfono.
  Future<Agenda?> obtenerAgenda(String id);

  /// La visita [id], o `null` si no está en el teléfono.
  Future<Visita?> obtenerVisita(String id);
}

/// La persistencia rechazó la operación por [motivo]; el repositorio la traduce a un `Failure`.
final class AgendaRechazadaException implements Exception {
  const AgendaRechazadaException(this.motivo);

  final MotivoRechazoAgenda motivo;

  @override
  String toString() => 'AgendaRechazadaException(${motivo.name})';
}

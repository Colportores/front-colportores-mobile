import '../../domain/entities/agenda.dart';
import '../../domain/entities/motivo_rechazo_agenda.dart';
import '../../domain/entities/nota_de_campo.dart';
import '../../domain/entities/visita.dart';
import '../../domain/entities/visita_guardada.dart';

/// Resultado de [AgendaLocalDataSource.agendar]: la agenda guardada y si ya estaba.
typedef AgendaAgendada = ({Agenda agenda, bool yaEstaba});

/// Resultado de [AgendaLocalDataSource.cancelar]: la agenda como quedó y si esta llamada escribió
/// (`false` si ya estaba cancelada).
typedef AgendaCancelada = ({Agenda agenda, bool escribio});

/// Resultado de [AgendaLocalDataSource.registrarVisita]: la visita guardada, si ya estaba y, si la
/// agenda indicada no servía, por qué se guardó sin ella.
typedef VisitaRegistrada = ({Visita visita, bool yaEstaba, MotivoAgendaIgnorada? agendaIgnorada});

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

  /// Guarda [visita] y su [nota] opcional. Con [agendaId], la agenda que la visita cumple pasa a
  /// `COMPLETADA` y apunta a la visita, en la misma transacción. Si ya hay una visita con ese `id`,
  /// no escribe nada y la devuelve con `yaEstaba: true`.
  ///
  /// Lanza [AgendaRechazadaException] si el vínculo de la visita no está en el teléfono. Si la
  /// agenda no existe, es de otra persona o ya no está pendiente, la visita se guarda igual como
  /// espontánea, sin tocar esa agenda, y el resultado trae el motivo en `agendaIgnorada`.
  Future<VisitaRegistrada> registrarVisita(Visita visita, {String? agendaId, NotaDeCampo? nota});

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

import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/agenda.dart';
import '../entities/nota_de_campo.dart';
import '../entities/visita.dart';
import '../entities/visita_guardada.dart';

/// Persistencia de las agendas y las visitas del colportor (BACK-HU-VIS-001, HU-VIS-001 y
/// HU-VIS-005).
///
/// Cada operación es **todo o nada**: guarda la fila, la encola para el sync (la fila entera, sin
/// notas: ADR-017), guarda la nota local-only y recalcula el color de la casa en la cache
/// `house_status` (R-UB08, ADR-003), en la misma transacción local. Nunca devuelve ni registra un
/// dato personal en un `Failure`.
abstract interface class AgendaRepository {
  /// Guarda [agenda] y su [nota] opcional. Si ya hay una agenda con ese `id`, no escribe nada y
  /// devuelve la que estaba (idempotente ante doble toque).
  ///
  /// El espacio y el vínculo persona ↔ espacio (si lo hay) tienen que estar en el teléfono: si no,
  /// `FailureValidacion` con el campo `espacio` o `persona`.
  Future<Either<Failure, Agenda>> agendar(Agenda agenda, {NotaDeCampo? nota});

  /// Pasa la agenda [agendaId] a `CANCELADA` en el instante [ahora]. Cancelar una agenda ya
  /// cancelada no escribe nada y devuelve la agenda. Una agenda cumplida o inexistente es un
  /// `FailureValidacion` con el campo `agenda`.
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora});

  /// Guarda [visita] y su [nota] opcional. Con [agendaId], la agenda que la visita cumple pasa a
  /// `CUMPLIDA` en la misma transacción. Si ya hay una visita con ese `id`, no escribe nada y
  /// devuelve la que estaba.
  ///
  /// Un espacio o una persona (si la hay) ausentes son un `FailureValidacion` con el campo `espacio`
  /// o `persona`. Una agenda inexistente, de otra casa o persona, o ya cerrada **no frena la
  /// visita**: se guarda como espontánea, la agenda no se toca y `VisitaGuardada.agendaIgnorada` dice
  /// por qué, para avisar sin perder lo registrado. Un resultado que no cumple la agenda
  /// (`TipoResultadoVisita.cumpleLaAgenda`: `NO_CONTESTO`) la pasa a `NO_CUMPLIDA` y
  /// `VisitaGuardada.agendaNoCumplida` lo dice.
  Future<Either<Failure, VisitaGuardada>> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  });

  /// La agenda de entrevista que sigue `PROGRAMADA` en [espacioId] (la más próxima), o `null` si no
  /// hay: la que una visita registrada ahí viene a cumplir. Solo lee.
  Future<Either<Failure, Agenda?>> agendaProgramadaDe(String espacioId);

  /// Deshace la visita [visitaId] (el «Deshacer» de «Guardado», vista 39 R·01): la da de baja con sus
  /// notas, devuelve a `PROGRAMADA` la agenda que había cumplido o no cumplido
  /// ([agendaAfectadaId]) o da de baja la que creó ([agendaCreadaId]) y recalcula el color de la casa,
  /// en una transacción. Deshacer dos veces no escribe nada la segunda. Una visita que no está en el
  /// teléfono es un `FailureValidacion` con el campo `visita`.
  Future<Either<Failure, Visita>> deshacerVisita(
    String visitaId, {
    String? agendaCreadaId,
    String? agendaAfectadaId,
    required DateTime ahora,
  });
}

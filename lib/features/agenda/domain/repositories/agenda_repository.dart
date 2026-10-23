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
  /// El vínculo persona ↔ espacio tiene que estar en el teléfono: si no, `FailureValidacion` con el
  /// campo `persona`.
  Future<Either<Failure, Agenda>> agendar(Agenda agenda, {NotaDeCampo? nota});

  /// Pasa la agenda [agendaId] a `CANCELADA` en el instante [ahora]. Cancelar una agenda ya
  /// cancelada no escribe nada y devuelve la agenda. Una agenda cumplida o inexistente es un
  /// `FailureValidacion` con el campo `agenda`.
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora});

  /// Guarda [visita] y su [nota] opcional. Con [agendaId], la agenda que la visita cumple pasa a
  /// `COMPLETADA` en la misma transacción. Si ya hay una visita con ese `id`, no escribe nada y
  /// devuelve la que estaba.
  ///
  /// Un vínculo ausente es un `FailureValidacion` con el campo `persona`. Una agenda inexistente,
  /// de otra persona o ya cerrada **no frena la visita**: se guarda como espontánea, la agenda no
  /// se toca y `VisitaGuardada.agendaIgnorada` dice por qué, para avisar sin perder lo registrado.
  Future<Either<Failure, VisitaGuardada>> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  });
}

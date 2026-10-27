// Doble de AgendaRepository para los tests de «Registrar visita» (vista 39, #411): registra lo que
// recibe, falla o espera cuando el test lo dice y se acuerda de los ids que repitieron.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/agenda_repository.dart';
import 'package:dartz/dartz.dart';

/// Un registro que le llegó al repositorio.
typedef VisitaRecibida = ({Visita visita, String? agendaId, NotaDeCampo? nota});

/// Un «Deshacer» que le llegó al repositorio.
typedef DeshechoRecibido = ({String visitaId, String? agendaCreadaId, String? agendaAfectadaId});

/// Una cancelación que le llegó al repositorio.
typedef CancelacionRecibida = ({String agendaId, DateTime ahora});

final class AgendaRepositorioFalso implements AgendaRepository {
  /// Cada [registrarVisita] toma el siguiente de [resultados] (`null` o sin más: éxito).
  final resultados = <Failure?>[];

  /// Cada [deshacerVisita] toma el siguiente de [resultadosDeshacer] (`null` o sin más: éxito).
  final resultadosDeshacer = <Failure?>[];

  /// Si no es `null`, [registrarVisita] espera a que se complete (un guardado «en curso»).
  Completer<void>? compuerta;

  /// Si no es `null`, [deshacerVisita] espera a que se complete.
  Completer<void>? compuertaDeshacer;

  /// Cada [cancelar] toma el siguiente de [resultadosCancelar] (`null` o sin más: éxito).
  final resultadosCancelar = <Failure?>[];

  /// Si no es `null`, [cancelar] espera a que se complete (una cancelación «en curso»).
  Completer<void>? compuertaCancelar;

  /// Si es `true`, [cancelar] lanza en vez de devolver un `Left` (una falla que se escapa).
  var cancelarLanza = false;

  /// La agenda programada de la casa que devuelve [agendaProgramadaDe].
  Agenda? programada;

  /// Si es `true`, [agendaProgramadaDe] falla (la lectura es de mejor esfuerzo).
  var fallaLaLecturaDeLaAgenda = false;

  /// Lo que dice el resultado de una visita con agenda: se copia a la [VisitaGuardada].
  var agendaNoCumplida = false;
  String? agendaCreadaId;
  String? agendaAfectadaId;

  final recibidas = <VisitaRecibida>[];
  final deshechas = <DeshechoRecibido>[];
  final canceladas = <CancelacionRecibida>[];

  @override
  Future<Either<Failure, VisitaGuardada>> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  }) async {
    recibidas.add((visita: visita, agendaId: agendaId, nota: nota));
    await compuerta?.future;
    final falla = resultados.isEmpty ? null : resultados.removeAt(0);
    if (falla != null) return Left(falla);
    return Right(
      VisitaGuardada(
        visita: visita,
        agendaNoCumplida: agendaNoCumplida,
        agendaCreadaId: agendaCreadaId,
        agendaAfectadaId: agendaAfectadaId,
      ),
    );
  }

  @override
  Future<Either<Failure, Visita>> deshacerVisita(
    String visitaId, {
    String? agendaCreadaId,
    String? agendaAfectadaId,
    required DateTime ahora,
  }) async {
    deshechas.add((
      visitaId: visitaId,
      agendaCreadaId: agendaCreadaId,
      agendaAfectadaId: agendaAfectadaId,
    ));
    await compuertaDeshacer?.future;
    final falla = resultadosDeshacer.isEmpty ? null : resultadosDeshacer.removeAt(0);
    if (falla != null) return Left(falla);
    final visita = recibidas.firstWhere((r) => r.visita.id == visitaId).visita;
    return Right(visita);
  }

  @override
  Future<Either<Failure, Agenda?>> agendaProgramadaDe(String espacioId) async {
    if (fallaLaLecturaDeLaAgenda) return const Left(FailureInesperado(causa: 'StateError'));
    return Right(programada);
  }

  @override
  Future<Either<Failure, Agenda>> agendar(Agenda agenda, {NotaDeCampo? nota}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora}) async {
    canceladas.add((agendaId: agendaId, ahora: ahora));
    await compuertaCancelar?.future;
    if (cancelarLanza) throw StateError('se cayó la base');
    final falla = resultadosCancelar.isEmpty ? null : resultadosCancelar.removeAt(0);
    if (falla != null) return Left(falla);
    return Right(agendaCanceladaFalsa(agendaId, ahora));
  }
}

/// La agenda de [id] como queda al cancelarla en [ahora].
Agenda agendaCanceladaFalsa(String id, DateTime ahora) => Agenda(
  id: id,
  espacioId: 'esp-1',
  tipo: TipoAgenda.entrevista,
  fechaProgramada: DateTime.utc(2026, 10, 27, 17),
  estado: EstadoAgenda.cancelada,
  colportorId: 'col-1',
  auditoria: Auditoria(createdAt: DateTime.utc(2026, 10, 20), updatedAt: ahora, createdBy: 'col-1'),
);

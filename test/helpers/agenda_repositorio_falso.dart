// Doble de AgendaRepository para los tests de «Registrar visita» (vista 39, #411): registra lo que
// recibe, falla o espera cuando el test lo dice y se acuerda de los ids que repitieron.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/agenda_repository.dart';
import 'package:dartz/dartz.dart';

/// Un registro que le llegó al repositorio.
typedef VisitaRecibida = ({Visita visita, String? agendaId, NotaDeCampo? nota});

/// Un «Deshacer» que le llegó al repositorio.
typedef DeshechoRecibido = ({String visitaId, String? agendaCreadaId, String? agendaAfectadaId});

final class AgendaRepositorioFalso implements AgendaRepository {
  /// Cada [registrarVisita] toma el siguiente de [resultados] (`null` o sin más: éxito).
  final resultados = <Failure?>[];

  /// Cada [deshacerVisita] toma el siguiente de [resultadosDeshacer] (`null` o sin más: éxito).
  final resultadosDeshacer = <Failure?>[];

  /// Si no es `null`, [registrarVisita] espera a que se complete (un guardado «en curso»).
  Completer<void>? compuerta;

  /// Si no es `null`, [deshacerVisita] espera a que se complete.
  Completer<void>? compuertaDeshacer;

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
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora}) =>
      throw UnimplementedError();
}

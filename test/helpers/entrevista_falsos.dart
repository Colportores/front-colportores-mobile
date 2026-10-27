// Dobles y semillas de la entrevista en curso (vista 39, R·05 a R·07; #450).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/entrevista_en_curso_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/entrevista_en_curso.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/agenda_repository.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/borrador_de_nota_de_entrevista.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/entrevista_en_curso_repository.dart';
import 'package:colportores_mobile/features/agenda/domain/services/destino_de_entrevista.dart';
import 'package:colportores_mobile/features/agenda/domain/services/ultima_visita_del_colportor.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/rotulo_entrevista_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// 23/10/2026, 14:41 en la zona del dispositivo.
final ahoraEntrevista = DateTime(2026, 10, 23, 14, 41);

/// Empezó a las 14:23.
final inicioEntrevista = DateTime(2026, 10, 23, 14, 23);

EntrevistaEnCurso entrevistaDePrueba({
  String colportorId = 'col-1',
  String espacioId = 'esp-1',
  String espacioPersonaId = 'ep-1',
  String visitaId = 'vis-1',
  String notaId = 'not-1',
  DateTime? inicio,
  String? agendaId,
  String? jornadaId,
}) => EntrevistaEnCurso(
  colportorId: colportorId,
  espacioId: espacioId,
  espacioPersonaId: espacioPersonaId,
  ids: IdsResultadoVisita(visita: visitaId, nota: notaId),
  inicio: inicio ?? inicioEntrevista,
  agendaId: agendaId,
  jornadaId: jornadaId,
);

/// El repositorio de visitas: anota lo que le llega, y se le puede trabar o romper.
final class AgendaFalsa implements AgendaRepository {
  final recibidas = <({Visita visita, String? agendaId, NotaDeCampo? nota})>[];

  /// Si no es `null`, el registro espera a que se complete.
  Completer<void>? compuerta;

  /// Si no es `null`, el registro devuelve esto.
  Failure? falla;

  /// Cuántos registros pasan antes de empezar a fallar con [falla] (0 = falla desde el primero).
  int fallaDesde = 0;

  @override
  Future<Either<Failure, VisitaGuardada>> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  }) async {
    if (compuerta case final c?) await c.future;
    recibidas.add((visita: visita, agendaId: agendaId, nota: nota));
    if (falla case final f? when recibidas.length > fallaDesde) {
      recibidas.removeLast();
      return Left(f);
    }
    // Idempotente por id, como el repositorio real: la segunda vez devuelve la que ya estaba.
    return Right(VisitaGuardada(visita: visita));
  }

  @override
  Future<Either<Failure, Agenda>> agendar(Agenda agenda, {NotaDeCampo? nota}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Agenda?>> agendaProgramadaDe(String espacioId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Visita>> deshacerVisita(
    String visitaId, {
    String? agendaCreadaId,
    String? agendaAfectadaId,
    required DateTime ahora,
  }) => throw UnimplementedError();
}

/// Un repositorio de entrevistas que se puede romper o trabar.
final class EntrevistaEnCursoRota implements EntrevistaEnCursoRepository {
  EntrevistaEnCursoRota(this.real);

  final EntrevistaEnCursoEnMemoria real;
  bool fallaAlLeer = false;
  bool fallaAlGuardar = false;
  bool fallaAlBorrar = false;

  @override
  Future<EntrevistaEnCurso?> leer(String colportorId) async {
    if (fallaAlLeer) throw StateError('no se puede leer');
    return real.leer(colportorId);
  }

  @override
  Future<void> guardar(EntrevistaEnCurso entrevista) async {
    if (fallaAlGuardar) throw StateError('no se puede guardar');
    return real.guardar(entrevista);
  }

  @override
  Future<void> borrar(String colportorId, {String? idVisita}) async {
    if (fallaAlBorrar) throw StateError('no se puede borrar');
    return real.borrar(colportorId, idVisita: idVisita);
  }
}

final class UltimaVisitaFalsa implements UltimaVisitaDelColportor {
  UltimaVisitaFalsa([this.fecha]);

  DateTime? fecha;
  bool falla = false;

  @override
  Future<DateTime?> fechaAntesDe(String colportorId, DateTime antesDe) async {
    if (falla) throw StateError('no se puede leer');
    return fecha;
  }
}

/// Dónde cuelga hoy la visita: por defecto, donde empezó la entrevista (la persona y el espacio
/// siguen). Un test lo cambia para la persona unida, dada de baja o la casa que ya no está.
final class DestinoFalso implements ResolverDestinoDeEntrevista {
  /// Si no es `null`, es lo que devuelve (`sinDestino` para «ya no hay dónde»).
  DestinoDeEntrevista? destino;

  /// Que devuelva `null`: ni la casa ni el depto siguen en el teléfono.
  bool sinDestino = false;
  bool falla = false;
  final consultas = <({String espacioId, String espacioPersonaId})>[];

  @override
  Future<DestinoDeEntrevista?> resolver({
    required String espacioId,
    required String espacioPersonaId,
  }) async {
    consultas.add((espacioId: espacioId, espacioPersonaId: espacioPersonaId));
    if (falla) throw StateError('no se puede leer');
    if (sinDestino) return null;
    return destino ?? DestinoDeEntrevista(espacioId: espacioId, espacioPersonaId: espacioPersonaId);
  }
}

/// El borrador de la nota de la entrevista (la base local cifrada): en un mapa, y se puede romper.
final class BorradorFalso implements BorradorDeNotaDeEntrevista {
  /// `notaId → texto`.
  final textos = <String, String>{};

  /// Cada escritura, en orden (`''` es un borrado por texto en blanco).
  final escrituras = <String>[];
  final borrados = <String>[];
  bool fallaAlLeer = false;
  bool fallaAlGuardar = false;

  /// Si no es `null`, la escritura espera a que se complete.
  Completer<void>? compuerta;

  @override
  Future<String> leer(String notaId) async {
    if (fallaAlLeer) throw StateError('no se puede leer');
    return textos[notaId] ?? '';
  }

  @override
  Future<void> guardar({
    required String notaId,
    required String visitaId,
    required String colportorId,
    required String texto,
    required DateTime ahora,
  }) async {
    if (compuerta case final c?) await c.future;
    if (fallaAlGuardar) throw StateError('no se puede guardar');
    escrituras.add(texto);
    if (texto.trim().isEmpty) {
      textos.remove(notaId);
    } else {
      textos[notaId] = texto;
    }
  }

  @override
  Future<void> borrar(String notaId) async {
    borrados.add(notaId);
    textos.remove(notaId);
  }
}

/// Lo que un test de pantalla necesita de la entrevista.
final class MontajeEntrevista {
  MontajeEntrevista({
    EntrevistaEnCursoEnMemoria? almacen,
    AgendaFalsa? agenda,
    UltimaVisitaFalsa? ultimaVisita,
    DestinoFalso? destino,
    BorradorFalso? borrador,
    DateTime Function()? reloj,
  }) : almacen = almacen ?? EntrevistaEnCursoEnMemoria(),
       agenda = agenda ?? AgendaFalsa(),
       ultimaVisita = ultimaVisita ?? UltimaVisitaFalsa(),
       destino = destino ?? DestinoFalso(),
       borrador = borrador ?? BorradorFalso(),
       reloj = reloj ?? (() => ahoraEntrevista);

  final EntrevistaEnCursoEnMemoria almacen;
  final AgendaFalsa agenda;
  final UltimaVisitaFalsa ultimaVisita;
  final DestinoFalso destino;
  final BorradorFalso borrador;
  DateTime Function() reloj;

  /// El lugar y la persona que se leen de la DB al mostrar la entrevista.
  RotuloEntrevista rotulo = (direccion: 'Grecia 3307', persona: 'Pedro Gómez');

  late final EntrevistaEnCursoRota rota = EntrevistaEnCursoRota(almacen);
  var _contador = 0;

  List<Override> get overrides => [
    entrevistaEnCursoRepositoryProvider.overrideWithValue(rota),
    agendaRepositoryProvider.overrideWithValue(agenda),
    ultimaVisitaDelColportorProvider.overrideWithValue(ultimaVisita),
    destinoDeEntrevistaProvider.overrideWithValue(destino),
    borradorDeNotaDeEntrevistaProvider.overrideWithValue(borrador),
    rotuloDeEntrevistaProvider.overrideWith((ref, entrevista) async => rotulo),
    relojEntrevistaProvider.overrideWithValue(() => reloj()),
    relojVisitaProvider.overrideWithValue(() => reloj().toUtc()),
    generadorIdEntrevistaProvider.overrideWithValue(() => 'id-${++_contador}'),
    generadorIdVisitaProvider.overrideWithValue(() => 'idv-${++_contador}'),
  ];
}

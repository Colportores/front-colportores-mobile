// Dobles de las notas de una persona (HU-UBI-012) para los tests de los casos de uso y de las pantallas.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/nota_persona_repository.dart';
import 'package:dartz/dartz.dart';

/// Una nota de [personaId] escrita a la hora local [creada] (por defecto, hoy a las 14:20 del 22/10).
NotaPersona notaDePrueba(
  String id,
  String texto, {
  String personaId = 'per-1',
  DateTime? creada,
  DateTime? borrada,
  DateTime? actualizada,
}) {
  final cuando = creada ?? DateTime(2026, 10, 22, 14, 20);
  return NotaPersona(
    id: id,
    personaId: personaId,
    texto: texto,
    auditoria: Auditoria(
      createdAt: cuando,
      updatedAt: actualizada ?? cuando,
      createdBy: 'col-1',
      deletedAt: borrada,
    ),
  );
}

/// [NotaPersonaRepository] en memoria.
///
/// - Cada operación toma el siguiente resultado de [resultados] (clave: `agregar`, `editar`, `borrar`,
///   `restaurar`; `null` = éxito, una [Failure] = ese fallo; si no queda, éxito).
/// - Si hay una compuerta de esa operación en [compuertas], espera a que se complete antes de
///   contestar (para tener una acción «en curso»).
/// - Guarda lo que recibió en [llamadas] (`operacion:id`), en orden.
class NotaPersonaRepositorioFalso implements NotaPersonaRepository {
  NotaPersonaRepositorioFalso({
    List<NotaPersona> notas = const [],
    this.contexto = const ContextoNotasPersona(nombre: 'María', soloLectura: false),
  }) {
    _notas.addAll(notas);
  }

  /// El contexto que lee la pantalla; `null` = la persona ya no está.
  ContextoNotasPersona? contexto;

  /// Si no es `null`, leer el contexto falla con esta.
  Failure? fallaDeContexto;

  final resultados = <String, List<Failure?>>{};
  final compuertas = <String, Completer<void>>{};
  final llamadas = <String>[];

  /// Los textos que llegaron a `agregar` y `editar`, en orden.
  final textosRecibidos = <String>[];

  final _notas = <NotaPersona>[];
  final _cambios = StreamController<List<NotaPersona>>.broadcast();

  List<NotaPersona> get notas => List.unmodifiable(_ordenadas());

  List<NotaPersona> _ordenadas() => [..._notas]
    ..sort((a, b) {
      final porFecha = b.auditoria.createdAt.compareTo(a.auditoria.createdAt);
      return porFecha != 0 ? porFecha : b.id.compareTo(a.id);
    });

  void _avisar() => _cambios.add(_ordenadas());

  int cuantas(String operacion) => llamadas.where((l) => l.startsWith('$operacion:')).length;

  Future<Failure?> _turno(String operacion, String id) async {
    llamadas.add('$operacion:$id');
    await compuertas[operacion]?.future;
    final cola = resultados[operacion];
    return cola == null || cola.isEmpty ? null : cola.removeAt(0);
  }

  int _indice(String id) => _notas.indexWhere((n) => n.id == id);

  @override
  Future<Either<Failure, NotaPersona>> agregar(NotaPersona nota) async {
    textosRecibidos.add(nota.texto);
    final falla = await _turno('agregar', nota.id);
    if (falla != null) return Left(falla);
    if (_indice(nota.id) == -1) {
      _notas.add(nota);
      _avisar();
    }
    return Right(_notas[_indice(nota.id)]);
  }

  @override
  Future<Either<Failure, NotaPersona>> editar({
    required String id,
    required String texto,
    required DateTime ahora,
  }) async {
    textosRecibidos.add(texto);
    final falla = await _turno('editar', id);
    if (falla != null) return Left(falla);
    final i = _indice(id);
    final vieja = _notas[i];
    _notas[i] = NotaPersona(
      id: vieja.id,
      personaId: vieja.personaId,
      texto: texto,
      auditoria: vieja.auditoria.copyWith(updatedAt: ahora),
    );
    _avisar();
    return Right(_notas[i]);
  }

  @override
  Future<Either<Failure, NotaPersona>> borrar({required String id, required DateTime ahora}) async {
    final falla = await _turno('borrar', id);
    if (falla != null) return Left(falla);
    final i = _indice(id);
    final vieja = _notas[i];
    if (!vieja.estaBorrada) {
      _notas[i] = NotaPersona(
        id: vieja.id,
        personaId: vieja.personaId,
        texto: vieja.texto,
        auditoria: vieja.auditoria.copyWith(updatedAt: ahora, deletedAt: ahora),
      );
      _avisar();
    }
    return Right(_notas[i]);
  }

  @override
  Future<Either<Failure, NotaPersona>> restaurar({
    required String id,
    required DateTime ahora,
  }) async {
    final falla = await _turno('restaurar', id);
    if (falla != null) return Left(falla);
    final i = _indice(id);
    final vieja = _notas[i];
    if (vieja.estaBorrada) {
      _notas[i] = NotaPersona(
        id: vieja.id,
        personaId: vieja.personaId,
        texto: vieja.texto,
        auditoria: vieja.auditoria.copyWith(updatedAt: ahora, deletedAt: null),
      );
      _avisar();
    }
    return Right(_notas[i]);
  }

  @override
  Stream<List<NotaPersona>> observar(String personaId) async* {
    yield _ordenadas();
    yield* _cambios.stream;
  }

  @override
  Future<Either<Failure, ContextoNotasPersona?>> leerContexto(String personaId) async {
    final falla = fallaDeContexto;
    return falla != null ? Left(falla) : Right(contexto);
  }
}

/// Repositorio cuya lista de notas nunca llega (el estado «cargando»).
final class NotaPersonaRepositorioCargando extends NotaPersonaRepositorioFalso {
  final _nunca = StreamController<List<NotaPersona>>();

  @override
  Stream<List<NotaPersona>> observar(String personaId) => _nunca.stream;
}

/// Repositorio cuya primera lectura de notas falla y la segunda sale bien (el «Reintentar»).
final class NotaPersonaRepositorioQueFallaUnaVez extends NotaPersonaRepositorioFalso {
  NotaPersonaRepositorioQueFallaUnaVez({super.notas});

  var lecturas = 0;

  @override
  Stream<List<NotaPersona>> observar(String personaId) {
    lecturas += 1;
    return lecturas == 1 ? Stream.error(StateError('no se pudo leer')) : super.observar(personaId);
  }
}

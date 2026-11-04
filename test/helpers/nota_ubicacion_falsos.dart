// Dobles de las notas de un lugar (vista 39, C·05) para los tests de los casos de uso y de la pestaña.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/nota_ubicacion_repository.dart';
import 'package:dartz/dartz.dart';

/// Una nota de [ubicacionId] escrita a la hora local [creada] (por defecto, el 22/10 a las 14:20).
NotaUbicacion notaDeLugar(
  String id,
  String texto, {
  String ubicacionId = 'ubi-1',
  DateTime? creada,
  DateTime? borrada,
  DateTime? actualizada,
}) {
  final cuando = creada ?? DateTime(2026, 10, 22, 14, 20);
  return NotaUbicacion(
    id: id,
    ubicacionId: ubicacionId,
    texto: texto,
    auditoria: Auditoria(
      createdAt: cuando,
      updatedAt: actualizada ?? cuando,
      createdBy: 'col-1',
      deletedAt: borrada,
    ),
  );
}

/// [NotaUbicacionRepository] en memoria.
///
/// - Cada operación toma el siguiente resultado de [resultados] (clave: `agregar`, `editar`, `borrar`,
///   `restaurar`; `null` = éxito, una [Failure] = ese fallo; si no queda, éxito).
/// - Si hay una compuerta de esa operación en [compuertas], espera a que se complete antes de
///   contestar (para tener una acción «en curso»).
/// - Guarda lo que recibió en [llamadas] (`operacion:id`), en orden.
class NotaUbicacionRepositorioFalso implements NotaUbicacionRepository {
  NotaUbicacionRepositorioFalso({List<NotaUbicacion> notas = const []}) {
    _notas.addAll(notas);
  }

  final resultados = <String, List<Failure?>>{};
  final compuertas = <String, Completer<void>>{};
  final llamadas = <String>[];

  /// Los textos que llegaron a `agregar` y `editar`, en orden.
  final textosRecibidos = <String>[];

  final _notas = <NotaUbicacion>[];
  final _cambios = StreamController<List<NotaUbicacion>>.broadcast();

  List<NotaUbicacion> get notas => List.unmodifiable(_ordenadas());

  List<NotaUbicacion> _ordenadas() => [..._notas]
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

  NotaUbicacion _con(NotaUbicacion n, {String? texto, required Auditoria auditoria}) =>
      NotaUbicacion(
        id: n.id,
        ubicacionId: n.ubicacionId,
        texto: texto ?? n.texto,
        auditoria: auditoria,
      );

  @override
  Future<Either<Failure, NotaUbicacion>> agregar(NotaUbicacion nota) async {
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
  Future<Either<Failure, NotaUbicacion>> editar({
    required String id,
    required String texto,
    required DateTime ahora,
  }) async {
    textosRecibidos.add(texto);
    final falla = await _turno('editar', id);
    if (falla != null) return Left(falla);
    final i = _indice(id);
    _notas[i] = _con(
      _notas[i],
      texto: texto,
      auditoria: _notas[i].auditoria.copyWith(updatedAt: ahora),
    );
    _avisar();
    return Right(_notas[i]);
  }

  @override
  Future<Either<Failure, NotaUbicacion>> borrar({
    required String id,
    required DateTime ahora,
  }) async {
    final falla = await _turno('borrar', id);
    if (falla != null) return Left(falla);
    final i = _indice(id);
    if (!_notas[i].estaBorrada) {
      _notas[i] = _con(
        _notas[i],
        auditoria: _notas[i].auditoria.copyWith(updatedAt: ahora, deletedAt: ahora),
      );
      _avisar();
    }
    return Right(_notas[i]);
  }

  @override
  Future<Either<Failure, NotaUbicacion>> restaurar({
    required String id,
    required DateTime ahora,
  }) async {
    final falla = await _turno('restaurar', id);
    if (falla != null) return Left(falla);
    final i = _indice(id);
    if (_notas[i].estaBorrada) {
      _notas[i] = _con(
        _notas[i],
        auditoria: _notas[i].auditoria.copyWith(updatedAt: ahora, deletedAt: null),
      );
      _avisar();
    }
    return Right(_notas[i]);
  }

  @override
  Stream<List<NotaUbicacion>> observar(String ubicacionId) async* {
    List<NotaUbicacion> delLugar(List<NotaUbicacion> todas) => [
      for (final n in todas)
        if (n.ubicacionId == ubicacionId) n,
    ];
    yield delLugar(_ordenadas());
    yield* _cambios.stream.map(delLugar);
  }
}

/// Repositorio cuya lista de notas nunca llega (el estado «cargando»).
final class NotaUbicacionRepositorioCargando extends NotaUbicacionRepositorioFalso {
  final _nunca = StreamController<List<NotaUbicacion>>();

  @override
  Stream<List<NotaUbicacion>> observar(String ubicacionId) => _nunca.stream;
}

/// Repositorio cuya primera lectura de notas falla y la segunda sale bien (el «Reintentar»).
final class NotaUbicacionRepositorioQueFallaUnaVez extends NotaUbicacionRepositorioFalso {
  NotaUbicacionRepositorioQueFallaUnaVez({super.notas});

  var lecturas = 0;

  @override
  Stream<List<NotaUbicacion>> observar(String ubicacionId) {
    lecturas += 1;
    return lecturas == 1
        ? Stream.error(StateError('no se pudo leer'))
        : super.observar(ubicacionId);
  }
}

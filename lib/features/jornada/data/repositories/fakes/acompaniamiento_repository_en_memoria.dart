import 'dart:async';

import 'package:dartz/dartz.dart';

import '../../../../../core/error/failure.dart';
import '../../../domain/entities/acompaniante.dart';
import '../../../domain/entities/tendencia_de_la_jornada.dart';
import '../../../domain/repositories/acompaniamiento_repository.dart';

/// El acompañamiento en memoria: lo usa la app cuando la DB local no está abierta y los tests, que
/// programan la lista, la falla y la espera de [guardar] y miran qué se guardó.
final class AcompaniamientoRepositoryEnMemoria implements AcompaniamientoRepository {
  AcompaniamientoRepositoryEnMemoria({this._lista = const [], this._tendencia});

  List<CoordinadorDeCampania> _lista;
  TendenciaDeLaJornada? _tendencia;
  final _cambios = StreamController<void>.broadcast(sync: true);
  final Map<String, List<String>> _acompanantes = {};

  /// Cada `guardar` que llegó, en orden: lo que se pidió dejar como acompañantes.
  final List<Set<String>> pedidos = [];

  /// Si no es `null`, el próximo `guardar` espera a que se complete (para probar dos acciones seguidas).
  Completer<void>? compuerta;

  /// Cuántos `guardar` fallan antes de volver a andar.
  int fallas = 0;

  /// La lista de coordinadores que se ofrece (vacía = todavía no bajó nada, 20J·05).
  set lista(List<CoordinadorDeCampania> valor) {
    _lista = valor;
    _cambios.add(null);
  }

  set tendencia(TendenciaDeLaJornada? valor) {
    _tendencia = valor;
    _cambios.add(null);
  }

  /// Lo guardado de [jornadaId] (para mirar en un test).
  List<String> guardadosDe(String jornadaId) => List.of(_acompanantes[jornadaId] ?? const []);

  Stream<T> _conCambios<T>(T Function() leer) async* {
    yield leer();
    await for (final _ in _cambios.stream) {
      yield leer();
    }
  }

  @override
  Stream<List<CoordinadorDeCampania>> observarLista({
    required String colportorId,
    Set<String>? campaniaIds,
  }) => _conCambios(
    () => [
      for (final c in _lista)
        if (c.usuarioId != colportorId) c,
    ],
  );

  @override
  Stream<List<Acompaniante>> observarDe(String jornadaId) => _conCambios(
    () => [
      for (final id in _acompanantes[jornadaId] ?? const <String>[])
        () {
          final c = _lista.where((c) => c.usuarioId == id).firstOrNull;
          return Acompaniante(usuarioId: id, nombre: c?.nombre, apellido: c?.apellido);
        }(),
    ],
  );

  @override
  Future<Either<Failure, Unit>> guardar({
    required String jornadaId,
    required String colportorId,
    required Set<String> usuarioIds,
  }) async {
    pedidos.add(Set.of(usuarioIds));
    final espera = compuerta;
    if (espera != null) await espera.future;
    if (fallas > 0) {
      fallas--;
      return const Left(FailureInesperado());
    }
    final actuales = _acompanantes[jornadaId] ?? <String>[];
    _acompanantes[jornadaId] = [
      for (final id in actuales)
        if (usuarioIds.contains(id)) id,
      for (final id in usuarioIds.toList()..sort())
        if (!actuales.contains(id)) id,
    ];
    _cambios.add(null);
    return const Right(unit);
  }

  @override
  Stream<TendenciaDeLaJornada?> observarTendencia({
    required String colportorId,
    required String jornadaId,
    required DateTime inicio,
    DateTime? fin,
    ({String desde, String? hasta})? campania,
  }) => _conCambios(() => campania == null ? null : _tendencia);
}

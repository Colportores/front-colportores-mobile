// Dobles de la ubicación alternativa de cobranza (HU-UBI-013, vista 22) para los tests de la ficha y
// del selector: un repositorio en memoria que el test maneja (lecturas, fallas, compuertas).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_alternativa_repository.dart';
import 'package:dartz/dartz.dart';

import 'persona_falsos.dart';

/// Una ubicación propia para elegir como alternativa (`ub-<id>`).
Ubicacion ubicacionParaAlternativa(
  String id, {
  String? calle = 'Av. Italia',
  String? numero = '2810',
  TipoUbicacion tipo = TipoUbicacion.negocio,
  double lat = -34.89,
  double lon = -56.16,
  DateTime? deletedAt,
}) => Ubicacion(
  id: id,
  tipo: tipo,
  calle: calle,
  numero: numero,
  lat: lat,
  lon: lon,
  ciudadId: 'mvd',
  auditoria: auditoriaPersonas(deletedAt: deletedAt),
);

/// [UbicacionAlternativaRepository] en memoria.
///
/// - [observar] y [observarCandidatas] emiten lo que se les pone con [ponerEstado] y [ponerCandidatas];
///   [sinLectura] y [errorAlObservar] arman el cargando y el error.
/// - [establecer] y [quitar] toman el siguiente resultado de [resultadosEstablecer] y
///   [resultadosQuitar] (`null` = sale bien y el estado cambia), y esperan a su compuerta si hay.
final class UbicacionAlternativaRepositorioFalso implements UbicacionAlternativaRepository {
  UbicacionAlternativaRepositorioFalso({
    EstadoUbicacionAlternativa inicial = const SinUbicacionAlternativa(),
    List<Ubicacion> candidatas = const [],
  }) : _estado = inicial {
    _candidatas = candidatas;
  }

  EstadoUbicacionAlternativa _estado;
  late List<Ubicacion> _candidatas;
  var _hayEstado = true;
  var _hayCandidatas = true;
  final _estados = StreamController<EstadoUbicacionAlternativa>.broadcast();
  final _listas = StreamController<List<Ubicacion>>.broadcast();

  /// Si no es `null`, [observar] falla con esto.
  Object? errorAlObservar;

  /// Si no es `null`, [observarCandidatas] falla con esto.
  Object? errorAlObservarCandidatas;

  var observaciones = 0;
  var observacionesDeCandidatas = 0;

  /// Lo que recibió [establecer] (`ubicacionId`) y [quitar] (la persona), en orden.
  final establecidas = <String>[];
  final quitadas = <String>[];

  /// Los resultados programados: `null` = sale bien; un `Failure` = falla; una excepción se lanza.
  final resultadosEstablecer = <Object?>[];
  final resultadosQuitar = <Object?>[];

  /// Si no es `null`, [establecer] / [quitar] esperan a que se complete.
  Completer<void>? compuertaEstablecer;
  Completer<void>? compuertaQuitar;

  /// El `colportorId` y el `espacioId` con los que se pidieron las candidatas.
  final pedidasCandidatas = <({String colportorId, String espacioId})>[];

  void sinLectura() => _hayEstado = false;
  void sinLecturaDeCandidatas() => _hayCandidatas = false;

  void ponerEstado(EstadoUbicacionAlternativa estado) {
    _estado = estado;
    _hayEstado = true;
    _estados.add(estado);
  }

  void ponerCandidatas(List<Ubicacion> candidatas) {
    _candidatas = candidatas;
    _hayCandidatas = true;
    _listas.add(candidatas);
  }

  EstadoUbicacionAlternativa get estado => _estado;

  @override
  Stream<EstadoUbicacionAlternativa> observar({
    required String personaId,
    required String espacioId,
  }) async* {
    observaciones += 1;
    final error = errorAlObservar;
    if (error != null) throw error;
    if (_hayEstado) yield _estado;
    yield* _estados.stream;
  }

  @override
  Stream<List<Ubicacion>> observarCandidatas({
    required String colportorId,
    required String espacioId,
  }) async* {
    observacionesDeCandidatas += 1;
    pedidasCandidatas.add((colportorId: colportorId, espacioId: espacioId));
    final error = errorAlObservarCandidatas;
    if (error != null) throw error;
    if (_hayCandidatas) yield _candidatas;
    yield* _listas.stream;
  }

  EspacioPersona _vinculo(String personaId, String espacioId, String? altId) => EspacioPersona(
    id: 'ep-$personaId',
    espacioId: espacioId,
    personaId: personaId,
    ubicacionCobranzaAltId: altId,
    auditoria: auditoriaPersonas(),
  );

  Object? _siguiente(List<Object?> resultados) =>
      resultados.isEmpty ? null : resultados.removeAt(0);

  @override
  Future<Either<Failure, EspacioPersona>> establecer({
    required String personaId,
    required String espacioId,
    required String ubicacionId,
    required String colportorId,
    required DateTime ahora,
  }) async {
    establecidas.add(ubicacionId);
    await compuertaEstablecer?.future;
    final r = _siguiente(resultadosEstablecer);
    if (r is Failure) return Left(r);
    if (r != null) throw r;
    final u = _candidatas.where((c) => c.id == ubicacionId).firstOrNull;
    ponerEstado(
      u == null ? UbicacionAlternativaFaltante(ubicacionId) : UbicacionAlternativaVigente(u),
    );
    return Right(_vinculo(personaId, espacioId, ubicacionId));
  }

  @override
  Future<Either<Failure, EspacioPersona>> quitar({
    required String personaId,
    required String espacioId,
    required DateTime ahora,
  }) async {
    quitadas.add(personaId);
    await compuertaQuitar?.future;
    final r = _siguiente(resultadosQuitar);
    if (r is Failure) return Left(r);
    if (r != null) throw r;
    ponerEstado(const SinUbicacionAlternativa());
    return Right(_vinculo(personaId, espacioId, null));
  }
}

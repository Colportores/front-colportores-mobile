import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/duplicado_ubicacion.dart';
import '../entities/estado_casa.dart';
import '../entities/resultado_union_duplicados.dart';
import '../entities/ubicacion.dart';
import '../entities/ubicacion_con_resumen.dart';
import '../repositories/pares_duplicados_repository.dart';
import '../repositories/ubicacion_repository.dart';
import '../services/criterio_duplicado_ubicacion.dart';

/// Parámetros de [ConsultarParesDuplicadosUseCase].
final class ConsultarParesDuplicadosParams extends Equatable {
  const ConsultarParesDuplicadosParams({required this.colportorId});

  /// El usuario con la sesión iniciada: se revisan sus ubicaciones (`created_by`).
  final String colportorId;

  @override
  List<Object?> get props => [colportorId];
}

/// Los pares que quedan para revisar: los de [criterio] entre [propias] menos los que el colportor
/// ya decidió y siguen escondidos en [ahora] (`ParDecidido.ocultaEn`).
List<ParDuplicado> _paresParaRevisar(
  CriterioDuplicadoUbicacion criterio,
  Iterable<Ubicacion> propias,
  Map<String, ParDecidido> decididos,
  DateTime ahora,
) => [
  for (final par in criterio.pares(propias))
    if (!(decididos[par.clave]?.ocultaEn(ahora) ?? false)) par,
];

/// HU-UBI-006 — el scan de "Posibles duplicados" (vista 10): los pares de ubicaciones propias y
/// activas que cumplen la regla de `CriterioDuplicadoUbicacion`, menos los que el colportor decidió:
/// «Son distintos» no vuelve nunca y «Ignorar» vuelve a los `ParDecidido.ventanaIgnorar`. El orden
/// es el del criterio.
///
/// Corre offline sobre la DB local y no escribe nada. Es la lectura de una vez; la pantalla usa
/// [ObservarParesDuplicadosUseCase], que además sigue los cambios.
final class ConsultarParesDuplicadosUseCase
    implements UseCase<List<ParDuplicado>, ConsultarParesDuplicadosParams> {
  ConsultarParesDuplicadosUseCase(
    this._ubicaciones,
    this._pares, {
    DateTime Function()? ahora,
    this._criterio = const CriterioDuplicadoUbicacion(),
  }) : _ahora = ahora ?? DateTime.now;

  final UbicacionRepository _ubicaciones;
  final ParesDuplicadosRepository _pares;
  final DateTime Function() _ahora;
  final CriterioDuplicadoUbicacion _criterio;

  @override
  Future<Either<Failure, List<ParDuplicado>>> call(ConsultarParesDuplicadosParams params) async {
    final colportorId = params.colportorId.trim();
    if (colportorId.isEmpty) {
      return const Left(
        FailureValidacion(campos: {'colportorId': 'No hay un colportor para revisar duplicados'}),
      );
    }

    final List<Ubicacion> propias;
    try {
      propias = await _ubicaciones.observarDelColportor(colportorId: colportorId).first;
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e));
    }

    final decididos = await _pares.decididos();
    return decididos.map((decididos) => _paresParaRevisar(_criterio, propias, decididos, _ahora()));
  }
}

/// Un par para revisar con lo que la pantalla muestra al lado de cada ubicación: cuántos espacios
/// tiene y, si se sabe, en qué estado está la casa. Las visitas todavía no están en el teléfono
/// (HU-VIS-005, #151) y no se inventan: el estado es `null` hasta que exista `house_status`.
final class ParaRevisar extends Equatable {
  const ParaRevisar({
    required this.par,
    required this.espaciosA,
    required this.espaciosB,
    this.estadoA,
    this.estadoB,
  });

  final ParDuplicado par;

  /// Espacios activos de `par.a` y de `par.b`.
  final int espaciosA;
  final int espaciosB;

  /// El estado de la casa de `par.a` y de `par.b`; `null` = no se sabe (ver [UbicacionConResumen]).
  final EstadoCasa? estadoA;
  final EstadoCasa? estadoB;

  @override
  List<Object?> get props => [par, espaciosA, espaciosB, estadoA, estadoB];
}

/// HU-UBI-006 — los pares de la vista 10, **reactivos**: se vuelven a emitir con cada alta, baja,
/// edición o decisión, así que un par unido, decidido o corregido sale de la lista solo. Es la misma
/// regla que [ConsultarParesDuplicadosUseCase].
///
/// Un error de lectura (de la lista o de las decisiones) sale como error del stream; el stream no
/// se corta: si había una lectura buena, sigue emitiendo con la última.
final class ObservarParesDuplicadosUseCase implements StreamUseCase<List<ParaRevisar>, String> {
  ObservarParesDuplicadosUseCase(
    this._ubicaciones,
    this._pares, {
    DateTime Function()? ahora,
    this._criterio = const CriterioDuplicadoUbicacion(),
  }) : _ahora = ahora ?? DateTime.now;

  final UbicacionRepository _ubicaciones;
  final ParesDuplicadosRepository _pares;
  final DateTime Function() _ahora;
  final CriterioDuplicadoUbicacion _criterio;

  @override
  Stream<List<ParaRevisar>> call(String colportorId) {
    final id = colportorId.trim();
    if (id.isEmpty) return Stream.error(StateError('No hay un colportor para revisar duplicados'));

    late final StreamController<List<ParaRevisar>> salida;
    StreamSubscription<List<UbicacionConResumen>>? lista;
    StreamSubscription<Map<String, ParDecidido>>? decisiones;
    List<UbicacionConResumen>? ultimaLista;
    Map<String, ParDecidido>? ultimasDecisiones;

    void emitir() {
      final propias = ultimaLista;
      final decididos = ultimasDecisiones;
      if (propias == null || decididos == null || salida.isClosed) return;
      final porId = {for (final u in propias) u.ubicacion.id: u};
      final pares = _paresParaRevisar(
        _criterio,
        [for (final u in propias) u.ubicacion],
        decididos,
        _ahora(),
      );
      salida.add([
        for (final par in pares)
          ParaRevisar(
            par: par,
            espaciosA: porId[par.a.id]?.cantidadEspacios ?? 0,
            espaciosB: porId[par.b.id]?.cantidadEspacios ?? 0,
            estadoA: porId[par.a.id]?.estado,
            estadoB: porId[par.b.id]?.estado,
          ),
      ]);
    }

    salida = StreamController<List<ParaRevisar>>(
      onListen: () {
        lista = _ubicaciones.observarListaDelColportor(colportorId: id).listen((propias) {
          ultimaLista = propias;
          emitir();
        }, onError: salida.addError);
        decisiones = _pares.observarDecididos().listen((decididos) {
          ultimasDecisiones = decididos;
          emitir();
        }, onError: salida.addError);
      },
      onCancel: () async {
        await lista?.cancel();
        await decisiones?.cancel();
      },
    );
    return salida.stream;
  }
}

/// Parámetros de [DecidirParDuplicadoUseCase].
final class DecidirParDuplicadoParams extends Equatable {
  const DecidirParDuplicadoParams({required this.par, required this.decision});

  final ParDuplicado par;
  final DecisionParDuplicado decision;

  @override
  List<Object?> get props => [par, decision];
}

/// HU-UBI-006 — «Son distintos» (`conservarAmbos`) o «Ignorar» un par del scan: guarda la decisión y
/// el par deja de aparecer (para siempre, o `ParDecidido.ventanaIgnorar`, "Escenario: Ignorar par").
/// No toca ninguna de las dos ubicaciones.
///
/// "Conservar ambos" sobre un par que no lo admite (misma dirección a menos de 100 m, D1):
/// `Left(FailureDuplicadoMismaDireccion)`, sin guardar nada. "Ignorar" vale para cualquier par.
final class DecidirParDuplicadoUseCase implements UseCase<Unit, DecidirParDuplicadoParams> {
  DecidirParDuplicadoUseCase(this._pares, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final ParesDuplicadosRepository _pares;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Unit>> call(DecidirParDuplicadoParams params) async {
    if (params.decision == DecisionParDuplicado.conservarAmbos &&
        !params.par.admiteConservarAmbos) {
      return const Left(FailureDuplicadoMismaDireccion());
    }
    return _pares.decidir(params.par, params.decision, ahora: _ahora());
  }
}

/// Parámetros de [UnirDuplicadosUseCase].
final class UnirDuplicadosParams extends Equatable {
  const UnirDuplicadosParams({required this.conservarId, required this.duplicadaId});

  /// La que queda (la «A» de «Conservar A y unir»; el colportor la puede elegir).
  final String conservarId;

  /// La que pasa a ser baja con sus espacios en la otra (la «B»).
  final String duplicadaId;

  @override
  List<Object?> get props => [conservarId, duplicadaId];
}

/// HU-UBI-006, «Marcar como duplicado y conservar A» («Conservar A y unir», vista 10): la unión
/// **local y definitiva** de un par, en una sola transacción (`UbicacionRepository.unirDuplicada`):
/// los espacios de B pasan a A, los únicos se funden, A pasa a edificio si queda con más de un
/// espacio, B queda de baja con el motivo `duplicado_de_A` en la auditoría local y se encola el
/// trabajo «marcar como duplicado».
///
/// **No espera nada**: los 8 s de «Deshacer» son de la pantalla (`UnionesPendientesNotifier`); este
/// caso de uso es lo que corre cuando se cumplen. En orden:
///
/// 1. Sin alguno de los dos `id`, o el mismo en los dos: `Left(FailureValidacion)`.
/// 2. La que se conserva no está: `Left(FailureUbicacionInexistente)`; está de baja: `Left(
///    FailureConservadaDeBaja)`. En los dos casos no escribe nada, para no dejar a las dos de baja.
/// 3. Si no, el resultado de la unión. Si B ya estaba unida y de baja, `ResultadoUnionDuplicados.
///    yaUnida`, sin encolar nada.
///
/// Todavía no se mueven las personas, visitas, ventas y cobranzas de B (no hay tablas locales
/// todavía: llegan con sus HU, #330); el servidor sí las pasa cuando aplica el trabajo.
final class UnirDuplicadosUseCase
    implements UseCase<ResultadoUnionDuplicados, UnirDuplicadosParams> {
  UnirDuplicadosUseCase(this._ubicaciones, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final UbicacionRepository _ubicaciones;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, ResultadoUnionDuplicados>> call(UnirDuplicadosParams params) {
    final conservarId = params.conservarId.trim();
    final duplicadaId = params.duplicadaId.trim();
    if (conservarId.isEmpty || duplicadaId.isEmpty || conservarId == duplicadaId) {
      return Future.value(
        const Left(
          FailureValidacion(campos: {'par': 'Elegí cuál de las dos ubicaciones se conserva'}),
        ),
      );
    }
    return _ubicaciones.unirDuplicada(conservarId, duplicadaId, ahora: _ahora());
  }
}

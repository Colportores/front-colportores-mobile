import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/duplicado_ubicacion.dart';
import '../entities/resultado_baja_ubicacion.dart';
import '../entities/ubicacion.dart';
import '../repositories/pares_duplicados_repository.dart';
import '../repositories/ubicacion_repository.dart';
import '../services/criterio_duplicado_ubicacion.dart';
import 'baja_ubicacion_use_cases.dart';

/// Parámetros de [ConsultarParesDuplicadosUseCase].
final class ConsultarParesDuplicadosParams extends Equatable {
  const ConsultarParesDuplicadosParams({required this.colportorId});

  /// El usuario con la sesión iniciada: se revisan sus ubicaciones (`created_by`).
  final String colportorId;

  @override
  List<Object?> get props => [colportorId];
}

/// HU-UBI-006 — el scan de "Posibles duplicados" (vista 10): los pares de ubicaciones propias y
/// activas que cumplen la regla de `CriterioDuplicadoUbicacion`, menos los que el colportor decidió
/// ("Conservar ambos", "Ignorar") hace menos de [ventana]. El orden es el del criterio. La cantidad
/// es el contador del aviso de la lista y del badge del menú (HU-NOT).
///
/// Corre offline sobre la DB local y no escribe nada. Cuándo corre ("diariamente o tras una
/// edición") lo decide quien lo llama: la pantalla y el planificador llegan con la vista 10 (#208).
final class ConsultarParesDuplicadosUseCase
    implements UseCase<List<ParDuplicado>, ConsultarParesDuplicadosParams> {
  ConsultarParesDuplicadosUseCase(
    this._ubicaciones,
    this._pares, {
    DateTime Function()? ahora,
    this._criterio = const CriterioDuplicadoUbicacion(),
  }) : _ahora = ahora ?? DateTime.now;

  /// HU-UBI-006: "Conservar histórico de 'ignorados' 30 días para no reaparecer constantemente".
  /// La vista 10 propone que "Son distintos" no vuelva nunca: para decidir en #207.
  static const ventana = Duration(days: 30);

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
    return decididos.map((decididos) {
      final desde = _ahora().subtract(ventana);
      return [
        for (final par in _criterio.pares(propias))
          if (!(decididos[par.clave]?.isAfter(desde) ?? false)) par,
      ];
    });
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

/// HU-UBI-006 — "Conservar ambos" o "Ignorar" un par del scan: guarda la decisión y el par deja de
/// aparecer durante `ConsultarParesDuplicadosUseCase.ventana` ("Escenario: Ignorar par"). No toca
/// ninguna de las dos ubicaciones.
///
/// "Conservar ambos" sobre un par que no lo admite (misma dirección con D1 en la opción (a)):
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

/// Parámetros de [MarcarDuplicadoUseCase].
final class MarcarDuplicadoParams extends Equatable {
  const MarcarDuplicadoParams({
    required this.conservarId,
    required this.duplicadaId,
    required this.baseUpdatedAtDuplicada,
    this.confirmaPendientes = false,
  });

  /// La que queda (la "A" de "Marcar como duplicado y conservar A"; el colportor la puede elegir).
  final String conservarId;

  /// La que se da de baja.
  final String duplicadaId;

  /// El `updated_at` de la duplicada tal como la cargó la pantalla (control de edición
  /// concurrente de la baja, HU-UBI-005).
  final DateTime baseUpdatedAtDuplicada;

  /// La segunda confirmación de la baja, tras ver `BajaRequiereConfirmacion`.
  final bool confirmaPendientes;

  @override
  List<Object?> get props => [conservarId, duplicadaId, baseUpdatedAtDuplicada, confirmaPendientes];
}

/// HU-UBI-006, "Escenario: Conservar A, baja a B": da de baja la duplicada con la baja de
/// HU-UBI-005 (`DarDeBajaUbicacionUseCase`: control de edición concurrente, aviso de pendientes,
/// tombstone encolado). En orden:
///
/// 1. Sin alguno de los dos `id`, o el mismo en los dos: `Left(FailureValidacion)`.
/// 2. La que se conserva no está: `Left(FailureUbicacionInexistente)`; está de baja (el par cambió
///    desde el scan): `Left(FailureConservadaDeBaja)`. En los dos casos no escribe nada, para no
///    dejar a las dos de baja.
/// 3. Si no, el resultado de la baja de la duplicada, tal cual. La condición del paso 2 se vuelve
///    a exigir **dentro de la transacción de la baja** (`conservadaId`): dos acciones concurrentes
///    sobre pares que se cruzan —conservar C y dar de baja A, conservar A y dar de baja B— pasan
///    las dos el paso 2, pero si la baja de A escribe primero, la otra encuentra A de baja y no
///    escribe. Así el resultado es siempre el de hacerlas una después de la otra.
///
/// **Pendiente** (#207): el `reason = "duplicado_de_A"` de la HU va como motivo de la baja
/// ([motivoBaja]), pero hoy el motivo no se guarda en ningún lado —ni la tabla local ni
/// `public.ubicacion` tienen dónde—: solo queda en el log que hubo motivo. Tampoco se mueven los
/// espacios, visitas ni clientes de la duplicada a la que se conserva (la vista 10 dice "pasan a
/// A"; la HU no lo pide): la duplicada queda de baja con lo suyo y se puede reactivar.
final class MarcarDuplicadoUseCase
    implements UseCase<ResultadoBajaUbicacion, MarcarDuplicadoParams> {
  MarcarDuplicadoUseCase(this._ubicaciones, this._darDeBaja);

  final UbicacionRepository _ubicaciones;
  final DarDeBajaUbicacionUseCase _darDeBaja;

  /// El `reason` de la HU para la baja de un duplicado de [conservadaId]. Punto único: cuando el
  /// esquema tenga dónde guardar el motivo, es lo que se guarda.
  static String motivoBaja(String conservadaId) => 'duplicado_de_$conservadaId';

  @override
  Future<Either<Failure, ResultadoBajaUbicacion>> call(MarcarDuplicadoParams params) async {
    final conservarId = params.conservarId.trim();
    final duplicadaId = params.duplicadaId.trim();
    if (conservarId.isEmpty || duplicadaId.isEmpty || conservarId == duplicadaId) {
      return const Left(
        FailureValidacion(campos: {'par': 'Elegí cuál de las dos ubicaciones se conserva'}),
      );
    }

    final leida = await _ubicaciones.obtener(conservarId);
    return leida.fold<Future<Either<Failure, ResultadoBajaUbicacion>>>(
      (falla) async => Left(falla),
      (conservada) async {
        if (conservada == null) return const Left(FailureUbicacionInexistente());
        if (conservada.estaBorrada) return const Left(FailureConservadaDeBaja());
        return _darDeBaja(
          DarDeBajaUbicacionParams(
            id: duplicadaId,
            baseUpdatedAt: params.baseUpdatedAtDuplicada,
            motivo: motivoBaja(conservarId),
            confirmaPendientes: params.confirmaPendientes,
            conservadaId: conservarId,
          ),
        );
      },
    );
  }
}

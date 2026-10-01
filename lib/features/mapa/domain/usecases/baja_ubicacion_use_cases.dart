import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/instante.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/resultado_baja_ubicacion.dart';
import '../entities/ubicacion.dart';
import '../repositories/ubicacion_repository.dart';
import '../services/consultor_pendientes_ubicacion.dart';

/// Parámetros de [DarDeBajaUbicacionUseCase].
final class DarDeBajaUbicacionParams extends Equatable {
  const DarDeBajaUbicacionParams({
    required this.id,
    required this.baseUpdatedAt,
    this.motivo,
    this.confirmaPendientes = false,
    this.conservadaId,
  });

  final String id;

  /// El `updated_at` de la ubicación tal como la pantalla la cargó: base del control de edición
  /// concurrente (igual que `ModificarUbicacionParams.baseUpdatedAt`).
  final DateTime baseUpdatedAt;

  /// Opcional (R-UB09, "`reason` si el usuario aporta"). Texto libre: no se imprime nunca.
  final String? motivo;

  /// La segunda confirmación, tras ver el resumen de [BajaRequiereConfirmacion].
  final bool confirmaPendientes;

  /// Otra ubicación que tiene que seguir activa **al escribir la baja**, en la misma transacción:
  /// la que se conserva al marcar un duplicado (HU-UBI-006). Si ya no lo está, la baja no se hace.
  final String? conservadaId;

  @override
  bool get stringify => false;

  @override
  List<Object?> get props => [id, baseUpdatedAt, motivo, confirmaPendientes, conservadaId];
}

/// HU-UBI-005 — Baja de ubicación (soft delete). En orden:
///
/// 1. Sin `id`: `Left(FailureValidacion)`. La ubicación no está: `Left(FailureUbicacionInexistente)`.
/// 2. Ya estaba de baja (doble toque): `Right(BajaSinCambios)`, sin escribir ni encolar.
/// 3. La fila cambió desde que se cargó la pantalla: `Left(FailureBajaCambioReciente)`.
/// 4. Con visitas pendientes, ventas con saldo o cobros sin cerrar y sin `confirmaPendientes`:
///    `Right(BajaRequiereConfirmacion)` con el resumen; no escribe.
/// 5. Escribe `deleted_at` = ahora y `updated_at` = ahora y encola el tombstone, en una
///    transacción. **No** da de baja los espacios ni las personas (HU: "no se borran en cascada").
///    Si otro toque la dio de baja mientras tanto, `Right(BajaSinCambios)`. Con
///    [DarDeBajaUbicacionParams.conservadaId], la transacción exige que esa otra siga activa.
///
/// Como `ModificarUbicacionUseCase`, no toca `sync_version`: el servidor la incrementa (0002).
final class DarDeBajaUbicacionUseCase
    implements UseCase<ResultadoBajaUbicacion, DarDeBajaUbicacionParams> {
  DarDeBajaUbicacionUseCase(this._repository, this._pendientes, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final UbicacionRepository _repository;
  final ConsultorPendientesUbicacion _pendientes;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, ResultadoBajaUbicacion>> call(DarDeBajaUbicacionParams params) async {
    final id = params.id.trim();
    if (id.isEmpty) return const Left(_sinId);

    final leida = await _repository.obtener(id);
    return leida.fold<Future<Either<Failure, ResultadoBajaUbicacion>>>(
      (falla) async => Left(falla),
      (actual) async {
        if (actual == null) return const Left(FailureUbicacionInexistente());
        if (actual.estaBorrada) return Right(BajaSinCambios(ubicacion: actual));
        if (actual.auditoria.updatedAt != instanteMs(params.baseUpdatedAt)) {
          return const Left(FailureBajaCambioReciente());
        }

        final pendientes = await _pendientes.de(id);
        final falla = pendientes.fold<Failure?>((f) => f, (_) => null);
        if (falla != null) return Left(falla);
        final resumen = pendientes.getOrElse(() => throw StateError('era un Left'));
        if (resumen.hayPendientes && !params.confirmaPendientes) {
          return Right(BajaRequiereConfirmacion(pendientes: resumen));
        }

        final motivo = params.motivo?.trim();
        final baja = await _repository.cambiarBaja(
          id,
          baja: true,
          baseUpdatedAt: params.baseUpdatedAt,
          ahora: _ahora(),
          conMotivo: motivo != null && motivo.isNotEmpty,
          conservadaId: params.conservadaId,
        );
        return baja.map<ResultadoBajaUbicacion>(
          (r) => r.escribio
              ? UbicacionDadaDeBaja(ubicacion: r.ubicacion)
              : BajaSinCambios(ubicacion: r.ubicacion),
        );
      },
    );
  }
}

/// Parámetros de [ReactivarUbicacionUseCase].
final class ReactivarUbicacionParams extends Equatable {
  const ReactivarUbicacionParams({required this.id, required this.baseUpdatedAt});

  final String id;

  /// El `updated_at` con el que "Ver bajas" cargó la ubicación.
  final DateTime baseUpdatedAt;

  @override
  List<Object?> get props => [id, baseUpdatedAt];
}

/// HU-UBI-005 — Reactivar desde "Ver bajas" (`deleted_at = NULL`). En orden: sin `id` o inexistente
/// como la baja; ya activa (doble toque): `Right` con la ubicación tal cual, sin escribir; la fila
/// cambió: `Left(FailureReactivacionCambioReciente)`; si no, escribe y encola el `update`.
///
/// **No** mira si la ciudad sigue en el catálogo (decisión de Cristian, 29/09): la ciudad es una
/// parte más de la dirección y ninguna acción sobre una ubicación se frena por eso.
///
/// No busca duplicados al reactivar (la HU no lo pide; sí lo hace la reactivación que va dentro de
/// editar, en `ModificarUbicacionUseCase`, HU-UBI-004): para confirmar.
final class ReactivarUbicacionUseCase implements UseCase<Ubicacion, ReactivarUbicacionParams> {
  ReactivarUbicacionUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final UbicacionRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Ubicacion>> call(ReactivarUbicacionParams params) async {
    final id = params.id.trim();
    if (id.isEmpty) return const Left(_sinId);

    final leida = await _repository.obtener(id);
    return leida.fold<Future<Either<Failure, Ubicacion>>>((falla) async => Left(falla), (
      actual,
    ) async {
      if (actual == null) return const Left(FailureUbicacionInexistente());
      if (!actual.estaBorrada) return Right(actual);
      if (actual.auditoria.updatedAt != instanteMs(params.baseUpdatedAt)) {
        return const Left(FailureReactivacionCambioReciente());
      }

      final reactivada = await _repository.cambiarBaja(
        id,
        baja: false,
        baseUpdatedAt: params.baseUpdatedAt,
        ahora: _ahora(),
      );
      return reactivada.map((r) => r.ubicacion);
    });
  }
}

const _sinId = FailureValidacion(campos: {'id': 'Falta la ubicación'});

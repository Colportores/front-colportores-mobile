import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/instante.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/resultado_baja_ubicacion.dart';
import '../entities/ubicacion.dart';
import '../repositories/ubicacion_repository.dart';
import '../services/catalogo_ciudades.dart';
import '../services/consultor_pendientes_ubicacion.dart';

/// Parámetros de [DarDeBajaUbicacionUseCase].
final class DarDeBajaUbicacionParams extends Equatable {
  const DarDeBajaUbicacionParams({
    required this.id,
    required this.baseUpdatedAt,
    this.motivo,
    this.confirmaPendientes = false,
  });

  final String id;

  /// El `updated_at` de la ubicación tal como la pantalla la cargó: base del control de edición
  /// concurrente (igual que `ModificarUbicacionParams.baseUpdatedAt`).
  final DateTime baseUpdatedAt;

  /// Opcional (R-UB09, "`reason` si el usuario aporta"). Texto libre: no se imprime nunca.
  final String? motivo;

  /// La segunda confirmación, tras ver el resumen de [BajaRequiereConfirmacion].
  final bool confirmaPendientes;

  @override
  bool get stringify => false;

  @override
  List<Object?> get props => [id, baseUpdatedAt, motivo, confirmaPendientes];
}

/// HU-UBI-005 — Baja de ubicación (soft delete). En orden:
///
/// 1. Sin `id`: `Left(FailureValidacion)`. La ubicación no está: `Left(FailureUbicacionInexistente)`.
/// 2. Ya estaba de baja (doble toque): `Right(BajaSinCambios)`, sin escribir ni encolar.
/// 3. La fila cambió desde que se cargó la pantalla: `Left(FailureUbicacionCambio)`.
/// 4. Con visitas pendientes, ventas con saldo o cobros sin cerrar y sin `confirmaPendientes`:
///    `Right(BajaRequiereConfirmacion)` con el resumen; no escribe.
/// 5. Escribe `deleted_at` = ahora y `updated_at` = ahora y encola el tombstone, en una
///    transacción. **No** da de baja los espacios ni las personas (HU: "no se borran en cascada").
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
          return const Left(FailureUbicacionCambio());
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
        );
        return baja.map((u) => UbicacionDadaDeBaja(ubicacion: u));
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
/// cambió: `Left(FailureUbicacionCambio)`; la ciudad ya no está en el [CatalogoCiudades]:
/// `Left(FailureCiudadFueraDeCatalogo)`; si no, escribe y encola el `update`.
///
/// No busca duplicados al reactivar (la HU no lo pide; sí lo hace la reactivación que va dentro de
/// editar, en `ModificarUbicacionUseCase`, HU-UBI-004): para confirmar.
final class ReactivarUbicacionUseCase implements UseCase<Ubicacion, ReactivarUbicacionParams> {
  ReactivarUbicacionUseCase(this._repository, this._catalogo, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final UbicacionRepository _repository;
  final CatalogoCiudades _catalogo;
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
        return const Left(FailureUbicacionCambio());
      }

      final existe = await _catalogo.existe(actual.ciudadId);
      final falla = existe.fold<Failure?>(
        (f) => f,
        (esta) => esta ? null : const FailureCiudadFueraDeCatalogo(),
      );
      if (falla != null) return Left(falla);

      return _repository.cambiarBaja(
        id,
        baja: false,
        baseUpdatedAt: params.baseUpdatedAt,
        ahora: _ahora(),
      );
    });
  }
}

const _sinId = FailureValidacion(campos: {'id': 'Falta la ubicación'});

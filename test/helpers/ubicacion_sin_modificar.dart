import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:dartz/dartz.dart';

/// Para los fakes de [UbicacionRepository] de los tests que no modifican ubicaciones: completa
/// los métodos de HU-UBI-004 (`obtener`, `contarEspaciosActivos`, `modificar`) sin usarlos, así
/// agregar uno a la interfaz no obliga a tocar cada fake.
mixin UbicacionRepositorySinModificar {
  Future<Either<Failure, Ubicacion?>> obtener(String id) => throw UnimplementedError();

  Future<Either<Failure, int>> contarEspaciosActivos(String ubicacionId) =>
      throw UnimplementedError();

  Future<Either<Failure, ResultadoModificacionUbicacion>> modificar(
    Ubicacion nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
  }) => throw UnimplementedError();

  Future<Either<Failure, Ubicacion>> cambiarBaja(
    String id, {
    required bool baja,
    required DateTime baseUpdatedAt,
    required DateTime ahora,
    bool conMotivo = false,
  }) => throw UnimplementedError();
}

/// Lo mismo para los fakes de [UbicacionLocalDataSource].
mixin UbicacionLocalSinModificar {
  Future<UbicacionModel?> obtener(String id) => throw UnimplementedError();

  Future<int> contarEspaciosActivos(String ubicacionId) => throw UnimplementedError();

  Future<UbicacionModel> cambiarBaja(
    String id, {
    required DateTime baseUpdatedAt,
    required DateTime updatedAt,
    required DateTime? deletedAt,
  }) => throw UnimplementedError();

  Future<UbicacionModel> actualizar(
    UbicacionModel nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
  }) => throw UnimplementedError();
}

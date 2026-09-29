import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../services/proveedor_gps.dart';
import '../value_objects/punto_capturado.dart';

/// HU-UBI-001 — toma la posición del GPS para el alta de ubicación.
///
/// - Sin GPS (permiso denegado, ubicación apagada, sin señal) devuelve el
///   `Left(FailureGpsNoDisponible)` del [ProveedorGps]: la pantalla ofrece "Marcar en el mapa".
/// - Una lectura en `(0, 0)` o fuera de rango se trata como sin GPS (caso borde de HU-UBI-001):
///   `Left(FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal))`.
/// - Una lectura imprecisa (> 50 m) **se devuelve igual**: la advertencia es al confirmar el alta
///   (`RegistrarUbicacionUseCase`), porque el colportor puede mover el marcador antes.
final class CapturarPosicionGpsUseCase implements UseCase<LecturaGps, NoParams> {
  CapturarPosicionGpsUseCase(this._gps);

  final ProveedorGps _gps;

  @override
  Future<Either<Failure, LecturaGps>> call(NoParams params) async {
    final lectura = await _gps.posicionActual();
    return lectura.fold(Left.new, (l) {
      final coordenadas = l.coordenadas;
      if (coordenadas.sonCero || !coordenadas.estanEnRango) {
        return const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal));
      }
      return Right(l);
    });
  }
}

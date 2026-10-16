import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/resumen_datos_locales.dart';
import '../repositories/datos_locales_repository.dart';

/// Cantidades de lo guardado en el teléfono: el resumen de HU-AUTH-010 y la advertencia de
/// operaciones sin sincronizar de HU-AUTH-006.
final class ObtenerResumenDatosLocalesUseCase implements UseCase<ResumenDatosLocales, NoParams> {
  const ObtenerResumenDatosLocalesUseCase(this._repository);

  final DatosLocalesRepository _repository;

  @override
  Future<Either<Failure, ResumenDatosLocales>> call(NoParams params) => _repository.resumen();
}

import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../services/sincronizador_manual.dart';

/// "Sincronizar ahora": sube lo pendiente antes de borrar los datos del teléfono (HU-AUTH-010).
final class SincronizarAhoraUseCase implements UseCase<Unit, NoParams> {
  const SincronizarAhoraUseCase(this._sincronizador);

  final SincronizadorManual _sincronizador;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) => _sincronizador.sincronizarAhora();
}

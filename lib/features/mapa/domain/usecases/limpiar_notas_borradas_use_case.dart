import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/limpieza_notas_borradas_repository.dart';

/// Borra para siempre las notas de persona que pasaron más de 90 días en «Ver borradas» (HU-UBI-012,
/// escenario «Nota borrada hace más de 90 días»). Se corre al abrir la app.
///
/// El reloj [_ahora] **no puede retroceder** (`RelojSesion`: el instante del equipo o el más alto que
/// ya vio): atrasar la hora del teléfono no estira la vida de una nota borrada. Si el reloj falla no se
/// borra nada: ante la duda la nota se conserva.
final class LimpiarNotasBorradasUseCase implements UseCase<int, NoParams> {
  const LimpiarNotasBorradasUseCase(this._repository, {required this._ahora});

  final LimpiezaNotasBorradasRepository _repository;
  final Future<DateTime> Function() _ahora;

  @override
  Future<Either<Failure, int>> call(NoParams params) async {
    final DateTime ahora;
    try {
      ahora = await _ahora();
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
    return _repository.purgarVencidas(ahora: ahora);
  }
}

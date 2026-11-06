import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/limpieza_notas_borradas_repository.dart';

/// Borra para siempre las notas de persona y de lugar que pasaron más de 90 días en «Ver borradas»
/// (HU-UBI-012, escenario «Nota borrada hace más de 90 días»; las del lugar, vista 39, mismo plazo). Se corre al abrir la app.
///
/// El «ahora» de la limpieza es el **menor** entre dos horas, y las dos hay que tenerlas:
/// - [_ahora], el reloj de la sesión, que no puede retroceder (`RelojSesion`: el instante del equipo o
///   el más alto que ya vio): atrasar la hora del teléfono no estira la vida de una nota borrada;
/// - [_horaDelServidor], la última `server_time` que contestó el servidor: adelantar la hora del
///   teléfono no la adelanta (decisión del agente de decisiones, #509 P3).
///
/// Si el teléfono nunca habló con el servidor, o si alguna hora falla, no se borra nada: ante la duda
/// la nota se conserva.
final class LimpiarNotasBorradasUseCase implements UseCase<int, NoParams> {
  const LimpiarNotasBorradasUseCase(
    this._repository, {
    required this._ahora,
    required this._horaDelServidor,
  });

  final LimpiezaNotasBorradasRepository _repository;
  final Future<DateTime> Function() _ahora;
  final Future<DateTime?> Function() _horaDelServidor;

  @override
  Future<Either<Failure, int>> call(NoParams params) async {
    final DateTime ahora;
    final DateTime? servidor;
    try {
      ahora = await _ahora();
      servidor = await _horaDelServidor();
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
    if (servidor == null) return const Right(0);
    return _repository.purgarVencidas(ahora: servidor.isBefore(ahora) ? servidor : ahora);
  }
}

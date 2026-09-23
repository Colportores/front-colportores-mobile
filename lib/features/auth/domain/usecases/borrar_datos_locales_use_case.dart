import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/resumen_datos_locales.dart';
import '../repositories/auth_repository.dart';
import '../repositories/datos_locales_repository.dart';

final class BorrarDatosLocalesParams extends Equatable {
  const BorrarDatosLocalesParams({required this.incluirBackupDrive});

  final bool incluirBackupDrive;

  @override
  List<Object?> get props => [incluirBackupDrive];
}

/// HU-AUTH-010 — Borra los datos del teléfono y después cierra la sesión (revocación del JWT como
/// en HU-AUTH-006; sin red o con el JWT vencido queda pendiente: best-effort).
///
/// El orden es a propósito: primero lo local, que no necesita red ("el borrado local procede
/// igual"). Si el borrado se niega (operaciones sin sincronizar) o falla, la sesión **no** se
/// cierra: el usuario sigue adentro, con sus datos, y puede reintentar.
final class BorrarDatosLocalesUseCase
    implements UseCase<ResultadoBorradoDatosLocales, BorrarDatosLocalesParams> {
  const BorrarDatosLocalesUseCase(this._datosLocales, this._auth);

  final DatosLocalesRepository _datosLocales;
  final AuthRepository _auth;

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> call(
    BorrarDatosLocalesParams params,
  ) async {
    final borrado = await _datosLocales.borrar(incluirBackupDrive: params.incluirBackupDrive);
    if (borrado.isLeft()) return borrado;

    // Los datos ya no están: la sesión se cierra pase lo que pase con la revocación (un `Left` acá
    // es que no se pudo borrar la sesión guardada; lo reporta el propio repositorio en el log).
    await _auth.cerrarSesion();
    return borrado;
  }
}

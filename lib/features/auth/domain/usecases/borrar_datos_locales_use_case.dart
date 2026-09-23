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
/// en HU-AUTH-006; sin red queda pendiente: best-effort).
///
/// El orden es a propósito: primero lo local, que no necesita red ("el borrado local procede
/// igual"). Mismo contrato que el cierre de sesión: si el borrado falla, o si la sesión guardada no
/// se pudo borrar después, devuelve el `Left` y la sesión **no** se da por cerrada — el usuario
/// sigue adentro y puede reintentar. Reintentar es seguro: el borrado es idempotente.
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

    final cierre = await _auth.cerrarSesion();
    return cierre.fold<Either<Failure, ResultadoBorradoDatosLocales>>(
      (f) => Left(f),
      (_) => borrado,
    );
  }
}

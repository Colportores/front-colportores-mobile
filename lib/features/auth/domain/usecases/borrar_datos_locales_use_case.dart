import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/resumen_datos_locales.dart';
import '../repositories/auth_repository.dart';
import '../repositories/datos_locales_repository.dart';

/// Etapas visibles del borrado (vista 19, artboard 06).
enum PasoBorrado {
  /// Pisando con ceros y eliminando el archivo de la DB local, y sus claves.
  borrandoDatos,

  /// Cerrando la sesión.
  cerrandoSesion,
}

final class BorrarDatosLocalesParams extends Equatable {
  const BorrarDatosLocalesParams({
    required this.incluirBackupDrive,
    this.reintento = false,
    this.alAvanzar,
  });

  final bool incluirBackupDrive;

  /// `true` si es el reintento de un borrado que ya empezó y falló a mitad: el teléfono puede tener
  /// la DB cerrada o a medio borrar, y no contarse. No se vuelve a bloquear por eso (el borrado es
  /// idempotente y terminarlo es lo que el usuario ya confirmó).
  final bool reintento;

  /// Avisa en qué etapa va. No se compara: no es parte de lo que se pide.
  final void Function(PasoBorrado paso)? alAvanzar;

  @override
  List<Object?> get props => [incluirBackupDrive, reintento];
}

/// HU-AUTH-010 — Borra los datos del teléfono y después cierra la sesión (revocación del JWT como
/// en HU-AUTH-006; sin red queda pendiente: best-effort).
///
/// **No descarta pendientes** (vista 19, #228): antes de tocar nada vuelve a contar, y si hay
/// operaciones sin sincronizar —o no se pudieron contar— devuelve `Left(FailureBorradoConPendientes)`
/// sin borrar. La pantalla ya bloquea "Continuar", pero entre el resumen y la confirmación puede
/// haberse sumado una operación.
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
    if (!params.reintento) {
      final resumen = await _datosLocales.resumen();
      switch (resumen) {
        case Left(value: final falla):
          // No se pudo revisar: sin saber si se pierde algo, no se borra.
          return Left(falla);
        case Right(value: final r) when r.operacionesSinSincronizar != 0:
          return Left(FailureBorradoConPendientes(pendientes: r.operacionesSinSincronizar));
        case Right():
          break;
      }
    }

    params.alAvanzar?.call(PasoBorrado.borrandoDatos);
    final borrado = await _datosLocales.borrar(
      incluirBackupDrive: params.incluirBackupDrive,
      reintento: params.reintento,
    );
    if (borrado.isLeft()) return borrado;

    params.alAvanzar?.call(PasoBorrado.cerrandoSesion);
    final cierre = await _auth.cerrarSesion();
    return cierre.fold<Either<Failure, ResultadoBorradoDatosLocales>>(
      (f) => Left(f),
      (_) => borrado,
    );
  }
}

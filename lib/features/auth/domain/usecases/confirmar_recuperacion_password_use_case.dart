import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/estado_db_local.dart';
import '../entities/politica_password.dart';
import '../repositories/db_local_repository.dart';
import '../repositories/recuperacion_password_repository.dart';
import '../services/turno_db_local.dart';

/// Parámetros de [ConfirmarRecuperacionPasswordUseCase].
final class ConfirmarRecuperacionPasswordParams extends Equatable {
  const ConfirmarRecuperacionPasswordParams({required this.nueva, required this.repetida});

  /// La contraseña nueva.
  final String nueva;

  /// La misma, escrita otra vez ("ingreso una nueva contraseña válida y la confirmo").
  final String repetida;

  /// [props] lleva las contraseñas en texto plano: sin esto, interpolar los params en un log las
  /// filtraría (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [nueva, repetida];
}

/// HU-AUTH-005 — Confirmación de recuperación de contraseña (ADR-006).
///
/// 1. Valida la contraseña nueva con la misma política que el registro, y que las dos coincidan.
/// 2. La fija en Supabase Auth con la sesión que abrió el enlace. Si ese paso falla, no se toca
///    nada más: el usuario puede corregir y reintentar.
/// 3. Si hay DB local en este dispositivo, **re-envuelve la DEK** con Argon2id(nueva contraseña):
///    la DEK sale del almacén seguro y el envoltorio anterior se reemplaza. La DB no se toca y en
///    ningún momento se pide la contraseña vieja. Corre en [TurnoDbLocal], como los otros flujos
///    de la DB local.
/// 4. Revoca todas las sesiones de la cuenta en todos los dispositivos (Supabase `signOut` con
///    scope global), incluida la de este: el usuario vuelve a entrar con la contraseña nueva.
///
/// Los pasos 3 y 4 no deshacen el 2: la contraseña ya cambió. Si fallan, el repositorio deja la
/// falla en el log y el resultado es igual un éxito, porque el usuario no puede hacer nada con eso.
/// Si el almacén seguro no deja leer la DEK, rige la recuperación guiada en el próximo inicio
/// (ADR-006): el envoltorio sigue con la contraseña anterior, y el aviso de "contraseña que no
/// abre" ya sugiere probar con la anterior.
final class ConfirmarRecuperacionPasswordUseCase
    implements UseCase<Unit, ConfirmarRecuperacionPasswordParams> {
  const ConfirmarRecuperacionPasswordUseCase(this._recuperacion, this._dbLocal, this._turno);

  final RecuperacionPasswordRepository _recuperacion;
  final DbLocalRepository _dbLocal;
  final TurnoDbLocal _turno;

  @override
  Future<Either<Failure, Unit>> call(ConfirmarRecuperacionPasswordParams params) async {
    final errores = <String, String>{};
    if (PoliticaPassword.validar(params.nueva, vacia: 'Ingresá la contraseña nueva')
        case final error?) {
      errores['password'] = error;
    }
    if (params.repetida.isEmpty) {
      errores['repetida'] = 'Repetí la contraseña nueva';
    } else if (params.repetida != params.nueva) {
      errores['repetida'] = 'Las contraseñas no coinciden';
    }
    if (errores.isNotEmpty) return Left(FailureValidacion(campos: errores));

    final actualizada = await _recuperacion.actualizarPassword(params.nueva);
    if (actualizada case Left(value: final falla)) return Left(falla);

    await _turno.enExclusiva(() => _reenvolverDek(params.nueva));
    await _recuperacion.cerrarTodasLasSesiones();
    return const Right(unit);
  }

  /// Re-envuelve la DEK si este dispositivo tiene DB local. Sin DB (dispositivo nuevo) no hay nada
  /// que envolver.
  Future<void> _reenvolverDek(String nueva) async {
    final estado = await _dbLocal.estado();
    if (estado case Right(value: EstadoDbLocal(archivoExiste: true, marca: MarcaDbLocal.puesta))) {
      final leida = await _dbLocal.leerDek();
      if (leida case Right(value: final ClaveDb dek)) {
        try {
          await _dbLocal.envolverConPassword(dek, nueva);
        } finally {
          dek.destruir();
        }
      }
    }
  }
}

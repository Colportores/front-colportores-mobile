import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/db_local_repository.dart';
import '../repositories/vigencia_sesion.dart';

/// Parámetros de [RecuperarDbLocalConPasswordUseCase].
final class RecuperarDbLocalParams extends Equatable {
  const RecuperarDbLocalParams({required this.password});

  /// Contraseña que el usuario ingresó en la pantalla de recuperación.
  final String password;

  /// [props] lleva la contraseña en texto plano: sin esto, interpolar los params en un log la
  /// filtraría (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [password];
}

/// Recuperación guiada de ADR-006: el almacén seguro falló (o perdió la DEK) con la DB en el
/// teléfono, y hay una DEK envuelta con la contraseña.
///
/// La UI llega acá después de [FailureAlmacenSeguroRecuperable] ("Tu almacenamiento seguro falló.
/// Ingresá tu contraseña para recuperar tus datos"). Con la contraseña:
/// 1. Argon2id desenvuelve la DEK (1 a 2 s). Si no abre, [FailurePasswordNoAbreDatos] y no se
///    toca nada: se puede reintentar.
/// 2. **Recién ahí** limpia el almacén seguro y lo reescribe con la DEK y la marca.
/// 3. Abre la DB con esa DEK. No se pierde nada.
///
/// Sin envoltorio (o ilegible) devuelve [FailureAlmacenSeguroSinRecuperacion]: la UI ofrece
/// "empezar de nuevo" y pregunta antes de borrar (`EmpezarDeNuevoDbLocalUseCase`).
///
/// Igual que la inicialización, antes de abrir verifica que la sesión siga vigente.
final class RecuperarDbLocalConPasswordUseCase implements UseCase<Unit, RecuperarDbLocalParams> {
  const RecuperarDbLocalConPasswordUseCase(this._repository, this._vigencia);

  final DbLocalRepository _repository;
  final VigenciaSesion _vigencia;

  @override
  Future<Either<Failure, Unit>> call(RecuperarDbLocalParams params) async {
    if (params.password.isEmpty) {
      return const Left(FailureValidacion(campos: {'password': 'Ingresá tu contraseña'}));
    }

    final testigo = _vigencia.tomarTestigo();
    if (testigo == null) return const Left(FailureSesionCerrada());

    final desenvuelta = await _repository.desenvolverConPassword(params.password);
    if (desenvuelta case Left(value: final falla)) return Left(falla);
    final dek = (desenvuelta as Right<Failure, ClaveDb>).value;

    final reconstruido = await _repository.reconstruirAlmacen(dek);
    if (reconstruido case Left(value: final falla)) {
      dek.destruir();
      return Left(falla);
    }

    return _repository.abrirSiSigueVigente(dek, testigo);
  }
}

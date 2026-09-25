import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/estado_db_local.dart';
import '../repositories/db_local_repository.dart';
import '../repositories/vigencia_sesion.dart';
import '../services/turno_db_local.dart';

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
/// 2. **Abre la DB con esa DEK.** Así se comprueba que es la buena antes de tocar el almacén: si no
///    abre, el almacén queda como estaba (puede tener la única DEK que sirve) y no se borra nada.
/// 3. Recién ahí limpia el almacén seguro y lo reescribe con la DEK y la marca. Si eso falla, la
///    DB queda abierta igual —los datos están— y el almacén se vuelve a reconstruir en la próxima
///    recuperación; la falla va al log.
///
/// Sin envoltorio (o ilegible) devuelve [FailureAlmacenSeguroSinRecuperacion]: la UI ofrece
/// "empezar de nuevo" y pregunta antes de borrar (`EmpezarDeNuevoDbLocalUseCase`). Un envoltorio de
/// una versión posterior de la app devuelve [FailureEsquemaPosterior], sin ofrecer borrar.
///
/// Corre dentro de [TurnoDbLocal], como la inicialización. Antes de abrir verifica que la sesión
/// siga vigente.
final class RecuperarDbLocalConPasswordUseCase implements UseCase<Unit, RecuperarDbLocalParams> {
  const RecuperarDbLocalConPasswordUseCase(this._repository, this._vigencia, this._turno);

  final DbLocalRepository _repository;
  final VigenciaSesion _vigencia;
  final TurnoDbLocal _turno;

  @override
  Future<Either<Failure, Unit>> call(RecuperarDbLocalParams params) async {
    if (params.password.isEmpty) {
      return const Left(FailureValidacion(campos: {'password': 'Ingresá tu contraseña'}));
    }

    final testigo = _vigencia.tomarTestigo();
    if (testigo == null) return const Left(FailureSesionCerrada());

    return _turno.enExclusiva(() => _recuperar(params.password, testigo));
  }

  Future<Either<Failure, Unit>> _recuperar(String password, TestigoSesion testigo) async {
    final estado = await _repository.estado();
    if (estado case Left(value: final falla)) return Left(falla);
    // Otro flujo ya la abrió mientras este esperaba el turno.
    if (estado case Right(value: EstadoDbLocal(abierta: true))) return const Right(unit);

    final desenvuelta = await _repository.desenvolverConPassword(password);
    if (desenvuelta case Left(value: final falla)) return Left(falla);
    final dek = (desenvuelta as Right<Failure, ClaveDb>).value;

    // La DB se queda con [dek] al abrir (y la destruye al cerrar sesión): el almacén se reescribe
    // con una copia propia.
    final paraElAlmacen = ClaveDb(Uint8List.fromList(dek.bytes));
    try {
      final abierta = await _repository.abrirSiSigueVigente(dek, testigo);
      if (abierta case Left(value: final falla)) return Left(falla);

      await _repository.reconstruirAlmacen(paraElAlmacen);
      return const Right(unit);
    } finally {
      paraElAlmacen.destruir();
    }
  }
}

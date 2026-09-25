import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/sesion.dart';
import '../repositories/auth_repository.dart';

/// HU-AUTH-009: confirma la contraseña de la cuenta de una sesión restaurada, que no la tiene y
/// la DB local la necesita para su envoltorio (revisión del PR #130). Es un login nuevo con el
/// mismo email, que además revoca la sesión que reemplaza (N3, ver
/// [AuthRepository.confirmarPassword]).
final class ConfirmarPasswordUseCase implements UseCase<Sesion, ConfirmarPasswordParams> {
  const ConfirmarPasswordUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, Sesion>> call(ConfirmarPasswordParams params) =>
      _repository.confirmarPassword(sesion: params.sesion, password: params.password);
}

final class ConfirmarPasswordParams extends Equatable {
  const ConfirmarPasswordParams({required this.sesion, required this.password});

  final Sesion sesion;
  final String password;

  /// Como `IniciarSesionParams`: sin esto, interpolar los params filtraría la contraseña.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [sesion, password];
}

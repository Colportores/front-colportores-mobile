import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/sesion.dart';
import '../repositories/auth_repository.dart';

/// HU-AUTH-003 — Inicio de sesión con Google.
///
/// No hay nada que validar: el proveedor recoge las credenciales en su propia pantalla. Si es
/// el primer ingreso, la cuenta queda registrada en el mismo paso (comportamiento de Supabase
/// Auth con OAuth); el alta del perfil en `public.usuario` la hace el BFF con los datos del
/// proveedor.
final class IniciarSesionConGoogleUseCase implements UseCase<Sesion, NoParams> {
  const IniciarSesionConGoogleUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, Sesion>> call(NoParams params) => _repository.iniciarSesionConGoogle();
}

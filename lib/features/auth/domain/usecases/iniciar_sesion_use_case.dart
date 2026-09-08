import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/sesion.dart';
import '../repositories/auth_repository.dart';

/// Parámetros de [IniciarSesionUseCase].
final class IniciarSesionParams extends Equatable {
  const IniciarSesionParams({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

/// HU-AUTH-003 — Inicio de sesión.
///
/// Plantilla de referencia para los casos de uso del proyecto:
/// 1. Valida la entrada y devuelve `Left(FailureValidacion)` con el detalle por campo.
/// 2. Normaliza (email en minúsculas, sin espacios).
/// 3. Delega en el repositorio; no conoce cómo se autentica ni dónde se guarda la sesión.
final class IniciarSesionUseCase implements UseCase<Sesion, IniciarSesionParams> {
  const IniciarSesionUseCase(this._repository);

  final AuthRepository _repository;

  static const int _minPassword = 8;
  static final RegExp _emailRegExp = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  Future<Either<Failure, Sesion>> call(IniciarSesionParams params) async {
    final email = params.email.trim().toLowerCase();
    final errores = <String, String>{};

    if (email.isEmpty) {
      errores['email'] = 'Ingresá tu email';
    } else if (!_emailRegExp.hasMatch(email)) {
      errores['email'] = 'El email no es válido';
    }

    if (params.password.isEmpty) {
      errores['password'] = 'Ingresá tu contraseña';
    } else if (params.password.length < _minPassword) {
      errores['password'] = 'La contraseña tiene al menos $_minPassword caracteres';
    }

    if (errores.isNotEmpty) return Left(FailureValidacion(campos: errores));

    return _repository.iniciarSesion(email: email, password: params.password);
  }
}

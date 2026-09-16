import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/sesion.dart';
import '../repositories/auth_repository.dart';

/// Parámetros de [RegistrarUsuarioUseCase].
final class RegistrarUsuarioParams extends Equatable {
  const RegistrarUsuarioParams({
    required this.nombre,
    required this.apellido,
    required this.cedula,
    required this.email,
    required this.password,
    required this.aceptaTerminos,
  });

  final String nombre;
  final String apellido;
  final String cedula;
  final String email;
  final String password;
  final bool aceptaTerminos;

  @override
  List<Object?> get props => [nombre, apellido, cedula, email, password, aceptaTerminos];
}

/// HU-AUTH-001 — Registro de cuenta (versión mockeada de hoy, ver issue #14).
///
/// 1. Valida la entrada y devuelve `Left(FailureValidacion)` con el detalle por campo (mismo
///    formato que [IniciarSesionUseCase]).
/// 2. Normaliza (nombre/apellido sin espacios, email en minúsculas, cédula a solo dígitos).
/// 3. Delega en el repositorio, que hoy registra contra el fake en memoria y deja la sesión
///    iniciada directamente.
///
/// Pendiente para las corridas con Supabase real (Opus): `signUp` de Supabase Auth exige
/// verificar el email antes de habilitar la cuenta (HU-AUTH-002); cuando eso llegue, este caso de
/// uso puede dejar de devolver una `Sesion` iniciada (quizás una cuenta pendiente, como ya existe
/// [FailureCuentaPendiente] para login). No decidido — no está documentado, queda para esa
/// corrida.
///
/// El dígito verificador de la cédula uruguaya tampoco está documentado: no se valida acá.
final class RegistrarUsuarioUseCase implements UseCase<Sesion, RegistrarUsuarioParams> {
  const RegistrarUsuarioUseCase(this._repository);

  final AuthRepository _repository;

  static final RegExp _emailRegExp = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _passwordRegExp = RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$');
  static final RegExp _cedulaFormatoRegExp = RegExp(r'^[\d.\-]+$');
  static final RegExp _cedulaNormalizadaRegExp = RegExp(r'^\d{7,8}$');

  @override
  Future<Either<Failure, Sesion>> call(RegistrarUsuarioParams params) async {
    final nombre = params.nombre.trim();
    final apellido = params.apellido.trim();
    final email = params.email.trim().toLowerCase();
    final cedula = params.cedula.trim();
    final cedulaNormalizada = cedula.replaceAll(RegExp(r'[.\-]'), '');
    final errores = <String, String>{};

    if (nombre.isEmpty) errores['nombre'] = 'Ingresá tu nombre';
    if (apellido.isEmpty) errores['apellido'] = 'Ingresá tu apellido';

    if (cedula.isEmpty) {
      errores['cedula'] = 'Ingresá tu cédula';
    } else if (!_cedulaFormatoRegExp.hasMatch(cedula) ||
        !_cedulaNormalizadaRegExp.hasMatch(cedulaNormalizada)) {
      errores['cedula'] = 'La cédula no es válida';
    }

    if (email.isEmpty) {
      errores['email'] = 'Ingresá tu email';
    } else if (!_emailRegExp.hasMatch(email)) {
      errores['email'] = 'El email no es válido';
    }

    if (params.password.isEmpty) {
      errores['password'] = 'Ingresá tu contraseña';
    } else if (!_passwordRegExp.hasMatch(params.password)) {
      errores['password'] = 'Usá al menos 8 caracteres, una mayúscula y un número.';
    }

    if (!params.aceptaTerminos) {
      errores['aceptaTerminos'] = 'Tenés que aceptar los términos.';
    }

    if (errores.isNotEmpty) return Left(FailureValidacion(campos: errores));

    return _repository.registrar(
      nombre: nombre,
      apellido: apellido,
      cedula: cedulaNormalizada,
      email: email,
      password: params.password,
    );
  }
}

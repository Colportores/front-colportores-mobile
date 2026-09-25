import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/politica_password.dart';
import '../entities/resultado_registro.dart';
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
    required this.aceptaTradeOffE2E,
  });

  final String nombre;
  final String apellido;
  final String cedula;
  final String email;
  final String password;
  final bool aceptaTerminos;

  /// Segunda casilla obligatoria de HU-AUTH-001 (R-AU05, issue #85): el usuario confirma que
  /// entendió el trade-off de la DEK envuelta (ADR-006) — sin la contraseña no se puede
  /// descifrar el backup, aunque conserve el teléfono (el Keystore abre la DB local igual).
  final bool aceptaTradeOffE2E;

  /// [props] lleva cédula, email y la contraseña en texto plano; `EquatableConfig.stringify`
  /// arranca en `true` en debug, así que sin esto cualquier interpolación de estos params
  /// filtraría esos datos (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    nombre,
    apellido,
    cedula,
    email,
    password,
    aceptaTerminos,
    aceptaTradeOffE2E,
  ];
}

/// HU-AUTH-001/002 — Registro de cuenta.
///
/// 1. Valida la entrada y devuelve `Left(FailureValidacion)` con el detalle por campo (mismo
///    formato que [IniciarSesionUseCase]).
/// 2. Normaliza (nombre/apellido sin espacios, email en minúsculas, cédula a solo dígitos).
/// 3. Delega en el repositorio. Con Supabase Auth real y "Confirm email" activo, `signUp` no deja
///    la sesión iniciada: el [ResultadoRegistro] vuelve con `sesion: null`
///    (`requiereVerificacion == true`) y la UI tiene que ofrecer verificar antes de entrar. El
///    fake en memoria no tiene ese paso y deja la sesión iniciada directamente.
///
/// El dígito verificador de la cédula uruguaya no está documentado: no se valida acá.
final class RegistrarUsuarioUseCase implements UseCase<ResultadoRegistro, RegistrarUsuarioParams> {
  const RegistrarUsuarioUseCase(this._repository);

  final AuthRepository _repository;

  static final RegExp _emailRegExp = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _cedulaFormatoRegExp = RegExp(r'^[\d.\-]+$');
  static final RegExp _cedulaNormalizadaRegExp = RegExp(r'^\d{7,8}$');

  @override
  Future<Either<Failure, ResultadoRegistro>> call(RegistrarUsuarioParams params) async {
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

    if (PoliticaPassword.validar(params.password) case final error?) {
      errores['password'] = error;
    }

    if (!params.aceptaTerminos) {
      errores['aceptaTerminos'] = 'Tenés que aceptar los términos.';
    }

    if (!params.aceptaTradeOffE2E) {
      errores['aceptaTradeOffE2E'] = 'Tenés que aceptar el trade-off de tu contraseña.';
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

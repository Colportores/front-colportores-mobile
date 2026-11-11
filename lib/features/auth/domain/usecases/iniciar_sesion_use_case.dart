import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/politica_password.dart';
import '../entities/sesion.dart';
import '../repositories/auth_repository.dart';
import '../services/validador_email.dart';

/// Parámetros de [IniciarSesionUseCase].
final class IniciarSesionParams extends Equatable {
  const IniciarSesionParams({required this.email, required this.password});

  final String email;
  final String password;

  /// [props] lleva el email y la contraseña en texto plano; `EquatableConfig.stringify` arranca
  /// en `true` en debug, así que sin esto cualquier interpolación de estos params (típicamente en
  /// un log de error o una excepción cuando el login falla) filtraría la contraseña
  /// (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [email, password];
}

/// HU-AUTH-003 — Inicio de sesión.
///
/// Plantilla de referencia para los casos de uso del proyecto:
/// 1. Valida la entrada y devuelve `Left(FailureValidacion)` con el detalle por campo (el formato
///    del email, con [ValidadorEmail]).
/// 2. Normaliza (email en minúsculas, sin espacios).
/// 3. Delega en el repositorio; no conoce cómo se autentica ni dónde se guarda la sesión.
///
/// Los avisos de cada campo ([avisoDelEmail], [avisoDeLaPassword]) son públicos para que el login
/// los muestre al salir del campo, sin esperar a «Entrar», con la misma regla y el mismo texto
/// (#700).
final class IniciarSesionUseCase implements UseCase<Sesion, IniciarSesionParams> {
  const IniciarSesionUseCase(this._repository);

  final AuthRepository _repository;

  /// Lo que dice el campo cuando el email está incompleto o mal armado.
  static const String _emailIncompleto = 'El email no es válido';

  /// Lo que dice el campo «CORREO» para [email] tal como se escribió (se normaliza acá), o `null`
  /// si pasa. Los textos son los de HU-AUTH-003.
  static String? avisoDelEmail(String email) {
    final normalizado = ValidadorEmail.normalizar(email);
    if (normalizado.isEmpty) return 'Ingresá tu email';
    return ValidadorEmail.mensaje(normalizado, siIncompleto: _emailIncompleto);
  }

  /// Lo que dice el campo «CONTRASEÑA» para [password], o `null` si pasa.
  ///
  /// El mínimo es el de la cuenta ([PoliticaPassword.largoMinimo], Supuesto S1 de HU-AUTH y
  /// `minimum_password_length` del servidor): ninguna cuenta tiene una contraseña más corta, así
  /// que no vale la pena mandarla. Se cuenta con el largo de la cadena, que nunca es menor que los
  /// caracteres visibles con los que cuenta el registro: no deja afuera ninguna contraseña que el
  /// registro haya aceptado. El login no mira mayúsculas ni números, ni lleva tope: la cuenta ya
  /// existe y el servidor la compara tal cual.
  static String? avisoDeLaPassword(String password) {
    if (password.isEmpty) return 'Ingresá tu contraseña';
    if (password.length < PoliticaPassword.largoMinimo) {
      return 'Completá tu contraseña: tiene al menos ${PoliticaPassword.largoMinimo} caracteres.';
    }
    return null;
  }

  @override
  Future<Either<Failure, Sesion>> call(IniciarSesionParams params) async {
    final email = ValidadorEmail.normalizar(params.email);
    final errores = <String, String>{};

    if (avisoDelEmail(params.email) case final aviso?) errores['email'] = aviso;
    if (avisoDeLaPassword(params.password) case final aviso?) errores['password'] = aviso;

    if (errores.isNotEmpty) return Left(FailureValidacion(campos: errores));

    return _repository.iniciarSesion(email: email, password: params.password);
  }
}

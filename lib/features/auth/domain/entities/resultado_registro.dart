import 'package:equatable/equatable.dart';

import 'sesion.dart';

/// Resultado de [RegistrarUsuarioUseCase] (HU-AUTH-001 / HU-AUTH-002).
///
/// Con "Confirm email" activo en Supabase Auth, `signUp` no deja la sesión iniciada: la cuenta
/// queda creada pero pendiente de que el usuario confirme el correo ([sesion] es `null` y
/// [requiereVerificacion] es `true`). El fake en memoria no tiene ese paso intermedio: siempre
/// devuelve sesión, salvo que se lo pida explícitamente (`requiereVerificacionAlRegistrar`).
final class ResultadoRegistro extends Equatable {
  const ResultadoRegistro({required this.sesion, required this.email});

  /// La sesión ya iniciada, o `null` si falta verificar el email.
  final Sesion? sesion;

  /// El email con el que se registró — la UI lo reofrece en el login si falta verificar.
  final String email;

  bool get requiereVerificacion => sesion == null;

  @override
  List<Object?> get props => [sesion, email];
}

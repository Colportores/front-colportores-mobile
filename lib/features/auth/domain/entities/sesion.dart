import 'package:equatable/equatable.dart';

/// Sesión autenticada del colportor.
///
/// Entidad de dominio: Dart puro + equatable (skill flutter-clean-arch, regla 1). No sabe cómo
/// se obtuvo (Supabase Auth) ni dónde se guarda (secure_storage).
class Sesion extends Equatable {
  const Sesion({
    required this.usuarioId,
    required this.email,
    required this.accessToken,
    required this.expiraEn,
  });

  /// UUID del usuario (`auth.users.id` = `public.usuario.id`). Es lo único que se loguea.
  final String usuarioId;

  /// Email de la cuenta del colportor (no es PII de clientes, pero tampoco se loguea).
  final String email;

  /// JWT que el BFF reenvía a Supabase. Nunca se persiste fuera de secure_storage.
  final String accessToken;

  final DateTime expiraEn;

  /// `true` si la sesión sigue válida en el instante [ahora] (inyectable para tests).
  bool estaVigente({DateTime? ahora}) => (ahora ?? DateTime.now()).isBefore(expiraEn);

  @override
  List<Object?> get props => [usuarioId, email, accessToken, expiraEn];
}

import 'package:equatable/equatable.dart';

import 'politica_sesion.dart';

/// Sesión autenticada del colportor.
///
/// Entidad de dominio: Dart puro + equatable (skill flutter-clean-arch, regla 1). No sabe cómo
/// se obtuvo (Supabase Auth) ni dónde se guarda (secure_storage).
class Sesion extends Equatable {
  Sesion({
    required this.usuarioId,
    required this.email,
    required this.accessToken,
    required DateTime expiraEn,
  }) : expiraEn = expiraEn.toUtc();

  /// UUID del usuario (`auth.users.id` = `public.usuario.id`). Es lo único que se loguea.
  final String usuarioId;

  /// Email de la cuenta del colportor (no es PII de clientes, pero tampoco se loguea).
  final String email;

  /// JWT que el BFF reenvía a Supabase. Nunca se persiste fuera de secure_storage.
  final String accessToken;

  /// Hasta cuándo vale la sesión sin actividad de red: la última vez que el servidor la emitió o
  /// la renovó, más 30 días (sesión deslizante, [PoliticaSesion], HU-AUTH-007). No es el
  /// vencimiento del JWT de acceso, que el proveedor renueva solo y dura mucho menos.
  ///
  /// Siempre en UTC — mismo invariante de fechas que `Auditoria`: `DateTime.==` mira `isUtc`
  /// y `hashCode` no, así que sin normalizar la misma sesión leída de distinta fuente daría
  /// desigual con el mismo `hashCode`.
  final DateTime expiraEn;

  /// `true` si la sesión sigue válida en el instante [ahora] (inyectable para tests), con la
  /// tolerancia de reloj de [PoliticaSesion].
  bool estaVigente({DateTime? ahora}) => !PoliticaSesion.vencida(expiraEn, ahora ?? DateTime.now());

  /// [props] lleva el email y el `accessToken`; `EquatableConfig.stringify` arranca en `true` en
  /// debug, así que sin esto cualquier interpolación del objeto o excepción que lo incluya
  /// filtraría el JWT en los logs (convenciones-desarrollo.md §7.5).
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [usuarioId, email, accessToken, expiraEn];
}

import 'package:equatable/equatable.dart';

/// Perfil del colportor registrado (HU-AUTH-001).
///
/// Entidad de dominio: Dart puro + equatable (skill flutter-clean-arch, regla 1). No sabe cómo
/// se registró (Supabase Auth `signUp`, hoy fake en memoria) ni dónde se persiste el perfil.
///
/// Pendiente: la persistencia local del perfil depende de la DB cifrada (#6, bloqueado); hasta
/// que se resuelva, esta entidad no se guarda en ningún lado — solo viaja en memoria durante el
/// registro.
class Usuario extends Equatable {
  const Usuario({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.cedula,
    required this.email,
  });

  /// UUID v7 (esquema-datos.md §Principios). Mismo id que tendrá `auth.users.id` cuando el
  /// registro real llegue a Supabase Auth.
  final String id;

  final String nombre;
  final String apellido;

  /// Solo dígitos (sin puntos ni guion) — ver [Usuario] y RegistrarUsuarioUseCase para la
  /// normalización. El dígito verificador de la cédula uruguaya no está documentado y no se
  /// valida acá: pendiente (issue #14).
  final String cedula;

  final String email;

  /// [props] lleva nombre, apellido, cédula y email; `EquatableConfig.stringify` arranca en
  /// `true` en debug, así que sin esto cualquier interpolación del objeto o `logger.d(usuario)`
  /// los imprimiría (convenciones-desarrollo.md §7.5, "sin PII en logs: solo IDs").
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [id, nombre, apellido, cedula, email];
}

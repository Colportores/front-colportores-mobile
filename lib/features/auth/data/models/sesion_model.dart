import '../../domain/entities/sesion.dart';

/// DTO de [Sesion]: la entidad más (de)serialización. Es lo único que cruza hacia los data sources.
///
/// Ojo con Equatable: compara también el `runtimeType`, así que un `SesionModel` **no es igual**
/// a una `Sesion` con los mismos datos. Los repositorios devuelven al dominio [toEntity], nunca
/// el modelo.
final class SesionModel extends Sesion {
  // Sin `const`: [Sesion] normaliza `expiraEn` a UTC en su lista de inicialización, así que su
  // constructor ya no puede ser const (y con un `DateTime` requerido nunca lo fue en la práctica).
  SesionModel({
    required super.usuarioId,
    required super.email,
    required super.accessToken,
    required super.expiraEn,
    super.entraConPassword,
  });

  factory SesionModel.fromEntity(Sesion sesion) => SesionModel(
    usuarioId: sesion.usuarioId,
    email: sesion.email,
    accessToken: sesion.accessToken,
    expiraEn: sesion.expiraEn,
    entraConPassword: sesion.entraConPassword,
  );

  factory SesionModel.fromJson(Map<String, Object?> json) => SesionModel(
    usuarioId: json['usuario_id']! as String,
    email: json['email']! as String,
    accessToken: json['access_token']! as String,
    expiraEn: DateTime.parse(json['expira_en']! as String).toUtc(),
    // Una sesión guardada antes de #130 no lo trae: ante la duda, con contraseña.
    entraConPassword: json['entra_con_password'] as bool? ?? true,
  );

  Sesion toEntity() => Sesion(
    usuarioId: usuarioId,
    email: email,
    accessToken: accessToken,
    expiraEn: expiraEn,
    entraConPassword: entraConPassword,
  );

  Map<String, Object?> toJson() => {
    'usuario_id': usuarioId,
    'email': email,
    'access_token': accessToken,
    'expira_en': expiraEn.toUtc().toIso8601String(),
    'entra_con_password': entraConPassword,
  };
}

import 'package:equatable/equatable.dart';

/// Intentos fallidos de contraseña en la confirmación final del borrado de datos locales
/// (HU-AUTH-010, vista 19) y, si se agotaron, hasta cuándo hay que esperar.
final class EstadoIntentosBorrado extends Equatable {
  EstadoIntentosBorrado({this.fallidos = 0, DateTime? bloqueadoHasta})
    : bloqueadoHasta = bloqueadoHasta?.toUtc();

  /// Sin intentos fallidos ni espera.
  static final limpio = EstadoIntentosBorrado();

  /// Contraseñas incorrectas desde el último intento bueno o desde que terminó la espera.
  final int fallidos;

  /// Fin de la espera, o `null` si no hay. Siempre en UTC.
  final DateTime? bloqueadoHasta;

  /// Si en [ahora] todavía hay que esperar.
  bool bloqueadoEn(DateTime ahora) => bloqueadoHasta != null && ahora.isBefore(bloqueadoHasta!);

  @override
  List<Object?> get props => [fallidos, bloqueadoHasta];
}

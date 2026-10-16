import 'package:equatable/equatable.dart';

import 'motivo_expiracion.dart';

/// Cómo y cuándo terminó la última sesión sin que la persona lo pidiera (HU-AUTH-007, vista 17):
/// venció por 30 días sin uso o la cerró el servidor. Es lo único que el teléfono recuerda del
/// cierre, aparte del correo de la cuenta (decisión de Cristian, 07/10): no lleva nombre, correo
/// ni nada de la sesión.
final class CierreForzado extends Equatable {
  /// [fecha] se guarda siempre en UTC.
  CierreForzado({required this.motivo, required DateTime fecha}) : fecha = fecha.toUtc();

  final MotivoExpiracion motivo;

  /// Cuándo se detectó el cierre. Siempre en UTC.
  final DateTime fecha;

  @override
  List<Object?> get props => [motivo, fecha];
}

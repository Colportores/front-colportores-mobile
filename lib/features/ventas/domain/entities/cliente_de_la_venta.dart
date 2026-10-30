import 'package:equatable/equatable.dart';

/// A quién se le vende: lo que muestra la tarjeta de arriba de la vista 27 («María Fernández»,
/// «Mataojo 2044 · Depto 3B») y el vínculo persona ↔ espacio al que se ata la venta.
///
/// Son datos de una persona: sin `toString` (convenciones §7.5) y nunca al log.
final class ClienteDeLaVenta extends Equatable {
  const ClienteDeLaVenta({
    required this.espacioPersonaId,
    required this.nombre,
    required this.direccion,
  });

  final String espacioPersonaId;
  final String nombre;

  /// «Mataojo 2044 · Depto 3B».
  final String direccion;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [espacioPersonaId, nombre, direccion];
}

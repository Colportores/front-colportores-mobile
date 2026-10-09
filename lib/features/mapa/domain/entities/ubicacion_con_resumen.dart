import 'package:equatable/equatable.dart';

import 'estado_casa.dart';
import 'ubicacion.dart';

/// Una ubicación con lo que la lista (HU-UBI-002) muestra al lado de la dirección: cuántos
/// espacios tiene y en qué estado está la casa.
final class UbicacionConResumen extends Equatable {
  const UbicacionConResumen({
    required this.ubicacion,
    this.cantidadEspacios = 0,
    this.estado,
    this.proximaEntrevista,
    this.motivoBaja,
  });

  final Ubicacion ubicacion;

  /// Espacios (deptos) sin baja de la ubicación.
  final int cantidadEspacios;

  /// El estado de la casa según `house_status`. **`null` = no se sabe**: todavía no hay tabla local
  /// de `house_status` (llega con HU-VIS-005, #151) y no se inventa «Sin visita» para todas. Cuando
  /// la fuente exista, una ubicación sin fila es [EstadoCasa.sinVisita], no `null`.
  final EstadoCasa? estado;

  /// La hora de la entrevista agendada, para [EstadoCasa.entrevistaAgendada]. Sin agenda local
  /// todavía, siempre `null`.
  final DateTime? proximaEntrevista;

  /// El motivo con que se dio de baja (`audit_log` local), si la ubicación está de baja y el
  /// teléfono lo guardó: una baja que vino del sync, o anterior a la versión 7 de la DB, no lo tiene.
  final String? motivoBaja;

  @override
  List<Object?> get props => [ubicacion, cantidadEspacios, estado, proximaEntrevista, motivoBaja];
}

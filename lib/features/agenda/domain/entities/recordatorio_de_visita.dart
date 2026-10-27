import 'package:equatable/equatable.dart';

import '../../../../core/domain/instante.dart';
import 'tipo_agenda.dart';

/// Lo que hace falta para avisar de una visita agendada (HU-NOT-002), sin el nombre del cliente:
/// el recordatorio lleva la hora, el tipo y la dirección, nada más.
class RecordatorioDeVisita extends Equatable {
  RecordatorioDeVisita({
    required this.agendaId,
    required this.tipo,
    required this.direccion,
    required DateTime fechaProgramada,
  }) : fechaProgramada = instanteMs(fechaProgramada);

  /// `agenda.id`: es también la clave del recordatorio. Programar de nuevo con el mismo id lo
  /// reemplaza; cancelar con ese id lo borra.
  final String agendaId;

  final TipoAgenda tipo;

  /// La dirección de la visita, ya armada para leerse («Av. Italia 1234»). Para una cobranza en otra
  /// dirección (`ubicacion_alt_id`) es la alternativa, no la de la casa (HU-VIS-006). Puede venir
  /// vacía: el texto sale sin «en …».
  final String direccion;

  /// Cuándo es la visita (no cuándo suena el aviso). UTC, al milisegundo.
  final DateTime fechaProgramada;

  @override
  List<Object?> get props => [agendaId, tipo, direccion, fechaProgramada];
}

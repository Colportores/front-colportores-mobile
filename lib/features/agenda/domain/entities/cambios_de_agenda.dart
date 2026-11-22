import 'package:equatable/equatable.dart';

import 'tipo_agenda.dart';

/// Lo que la colportora deja en el formulario «Modificar agenda» (vista 23, 23C·02): el estado final
/// de los campos editables, no una lista de diferencias. El repositorio compara con lo guardado y
/// escribe solo si algo cambió.
///
/// **Lleva la nota** (dato personal): nunca debe salir en un log ni en un `toString`.
class CambiosDeAgenda extends Equatable {
  const CambiosDeAgenda({
    required this.agendaId,
    required this.tipo,
    required this.fechaProgramada,
    this.slotCodigo,
    this.nota,
    required this.idNota,
  });

  final String agendaId;

  final TipoAgenda tipo;

  /// Cuándo es la visita (hora local, al minuto; la entidad la lleva a UTC).
  final DateTime fechaProgramada;

  /// La franja (`agenda.slot_codigo`); `null`: sin franja.
  final String? slotCodigo;

  /// El texto de la nota. `null`: no se toca la nota. En blanco: se borra la que había.
  final String? nota;

  /// El id (UUID v7) para la nota si hay que crearla. Se genera una vez por formulario y se repite en
  /// cada intento: un doble toque o un reintento no crean dos notas.
  final String idNota;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [agendaId, tipo, fechaProgramada, slotCodigo, nota, idNota];
}

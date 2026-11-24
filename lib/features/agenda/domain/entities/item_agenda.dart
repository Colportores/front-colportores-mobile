import 'package:equatable/equatable.dart';

import '../../../mapa/domain/entities/ubicacion.dart';
import '../../../mapa/domain/value_objects/coordenadas.dart';
import 'agenda.dart';
import 'estado_agenda.dart';

/// La dirección de una ubicación tal como la muestra la agenda: calle y número, sin coordenadas ni
/// nada más. [deBaja] es que la ubicación está dada de baja (solo se mira en la alternativa de una
/// cobranza: la casa de la cita dada de baja oculta la agenda entera). [coordenadas] es el punto de
/// la ubicación (la distancia de la hoja «Agendados» del mapa, 06C·03); `null` si no se leyó.
class DireccionDeAgenda extends Equatable {
  const DireccionDeAgenda({
    required this.ubicacionId,
    required this.tipo,
    this.calle,
    this.numero,
    this.deBaja = false,
    this.coordenadas,
  });

  final String ubicacionId;
  final TipoUbicacion tipo;
  final String? calle;
  final String? numero;
  final bool deBaja;
  final Coordenadas? coordenadas;

  @override
  List<Object?> get props => [ubicacionId, tipo, calle, numero, deBaja, coordenadas];
}

/// Una fila de la agenda del colportor (HU-VIS-002): la [agenda] y lo que hace falta para
/// reconocerla de un vistazo —con quién es y dónde— sin volver a pedirlo.
///
/// - [personaNombre] y [personaApellido] son datos personales (R-UB09): viven solo en el teléfono, se
///   dibujan en la fila y **nunca** van a un log, a la telemetría ni al `toString` (por eso
///   `stringify` está apagado, como en `Persona`).
/// - [casa] es la ubicación del espacio de la cita y [numeroDepto] el depto, si lo tiene. [alternativa]
///   es la dirección de cobranza distinta (`agenda.ubicacion_alt_id`), si la hay. Las dos son `null`
///   si la fila todavía no llegó al teléfono (un pull incompleto): la cita se muestra igual, sin
///   dirección.
class ItemAgenda extends Equatable {
  const ItemAgenda({
    required this.agenda,
    this.personaNombre,
    this.personaApellido,
    this.casa,
    this.numeroDepto,
    this.alternativa,
  });

  final Agenda agenda;
  final String? personaNombre;
  final String? personaApellido;
  final DireccionDeAgenda? casa;
  final String? numeroDepto;
  final DireccionDeAgenda? alternativa;

  /// «Ana Martínez», o `null` si la cita no tiene persona (o su nombre quedó vacío).
  String? get nombrePersona {
    final partes = [
      for (final p in [personaNombre, personaApellido])
        if (p != null && p.trim().isNotEmpty) p.trim(),
    ];
    return partes.isEmpty ? null : partes.join(' ');
  }

  /// La dirección a la que hay que ir: la alternativa de la cobranza si la tiene; si no, la casa.
  DireccionDeAgenda? get lugar => alternativa ?? casa;

  /// La cobranza va a una dirección alternativa que se dio de baja (la cita sigue y suena, pero la
  /// dirección se ve marcada: «Alt. de baja»).
  bool get lugarDadoDeBaja => lugar?.deBaja ?? false;

  /// La cita sigue esperando su visita y su hora ya pasó (23B·02): se muestra en «Pendientes» con
  /// «Registrar» hasta que se registre qué pasó (decisión de Cristian, 23/10, «Los de la HU»: la
  /// vencida no pasa sola a «no cumplida»).
  bool estaVencida(DateTime ahora) =>
      agenda.estado == EstadoAgenda.programada && agenda.fechaProgramada.isBefore(ahora.toUtc());

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    agenda,
    personaNombre,
    personaApellido,
    casa,
    numeroDepto,
    alternativa,
  ];
}

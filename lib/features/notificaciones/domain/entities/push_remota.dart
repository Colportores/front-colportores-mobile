import 'package:equatable/equatable.dart';

import 'tipo_notificacion.dart';

/// Los tipos de push remota que la app sabe leer (HU-NOT-003, «Payload remoto: tipo de evento +
/// UUIDs relevantes»; contrato decidido el 03/11, backend-supabase#237). [codigo] es el `type` del
/// payload, [claveId] el campo con el UUID que lo acompaña (`null` si no lleva ninguno) y
/// [claveIdOpcional] un segundo UUID que puede faltar. Cada tipo nuevo es una línea acá, con su
/// texto en [TextosPushRemota] y su [TipoNotificacion].
enum TipoPushRemota {
  /// El coordinador autorizó un pedido de la colportora: `{type: "pedido_autorizado", pedido_id}`.
  pedidoAutorizado(
    codigo: 'pedido_autorizado',
    claveId: 'pedido_id',
    tipoDeAviso: TipoNotificacion.pedidoAutorizado,
  ),

  /// El coordinador validó un ticket: `{type: "ticket_validado", ticket_id}`.
  ticketValidado(
    codigo: 'ticket_validado',
    claveId: 'ticket_id',
    tipoDeAviso: TipoNotificacion.ticketValidado,
  ),

  /// El coordinador rechazó un ticket: `{type: "ticket_rechazado", ticket_id}`.
  ticketRechazado(
    codigo: 'ticket_rechazado',
    claveId: 'ticket_id',
    tipoDeAviso: TipoNotificacion.ticketRechazado,
  ),

  /// La colportora quedó asignada a una campaña, y a una zona si ya la tiene:
  /// `{type: "asignacion_campania", campania_id, zona_id?}`.
  asignacionCampania(
    codigo: 'asignacion_campania',
    claveId: 'campania_id',
    claveIdOpcional: 'zona_id',
    tipoDeAviso: TipoNotificacion.asignacionCampania,
  ),

  /// Una cuota venció hace 3 días; cada cuota es una cita de cobranza de la agenda:
  /// `{type: "cuota_pendiente", agenda_id}`.
  cuotaPendiente(
    codigo: 'cuota_pendiente',
    claveId: 'agenda_id',
    tipoDeAviso: TipoNotificacion.cuotaPendiente,
  ),

  /// Aviso nocturno de las visitas de mañana, sin id: `{type: "agenda_manana"}`.
  agendaManana(codigo: 'agenda_manana', claveId: null, tipoDeAviso: TipoNotificacion.agendaManana);

  const TipoPushRemota({
    required this.codigo,
    required this.claveId,
    this.claveIdOpcional,
    required this.tipoDeAviso,
  });

  final String codigo;
  final String? claveId;
  final String? claveIdOpcional;

  /// Cómo se guarda en el historial.
  final TipoNotificacion tipoDeAviso;

  /// `null` si [codigo] no es de un tipo conocido (una versión de la app más vieja que el servidor).
  static TipoPushRemota? desdeCodigo(String codigo) {
    for (final tipo in values) {
      if (tipo.codigo == codigo) return tipo;
    }
    return null;
  }
}

/// Una push remota ya leída y validada: de qué evento se trata y a qué filas apunta. Nunca trae texto
/// de la persona (R-NO02): el texto del aviso lo arma la app.
class PushRemota extends Equatable {
  const PushRemota({
    required this.tipo,
    required this.eventoId,
    this.entidadId,
    this.entidadOpcionalId,
  });

  final TipoPushRemota tipo;

  /// Identifica el evento: el mismo [eventoId] no genera dos avisos (idempotencia).
  final String eventoId;

  /// El UUID de la fila a la que apunta (el pedido, el ticket, la campaña, la agenda); `null` en un
  /// tipo sin id (`agenda_manana`).
  final String? entidadId;

  /// El segundo UUID, si el tipo lo admite y vino (la zona de `asignacion_campania`).
  final String? entidadOpcionalId;

  @override
  List<Object?> get props => [tipo, eventoId, entidadId, entidadOpcionalId];
}

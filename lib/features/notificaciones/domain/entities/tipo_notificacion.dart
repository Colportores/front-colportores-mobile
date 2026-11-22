/// De qué trata un aviso del centro de notificaciones (HU-NOT-005). [codigo] es el valor de la
/// columna `tipo` de `notificacion_historial`.
///
/// Los avisos que llegan por push (HU-NOT-003, S11; decisión de Cristian del 06/10, «Notif. S8»):
/// cada tipo nuevo es una línea acá.
enum TipoNotificacion {
  /// El recordatorio local de una visita agendada (HU-NOT-002).
  recordatorioVisita('RECORDATORIO_VISITA'),

  /// El coordinador autorizó un pedido (push remota, HU-NOT-003).
  pedidoAutorizado('PEDIDO_AUTORIZADO'),

  /// Un ticket validado por el coordinador (push remota).
  ticketValidado('TICKET_VALIDADO'),

  /// Un ticket rechazado por el coordinador (push remota).
  ticketRechazado('TICKET_RECHAZADO'),

  /// La colportora quedó asignada a una campaña o a una zona (push remota).
  asignacionCampania('ASIGNACION_CAMPANIA'),

  /// Una cuota pendiente hace 3 días (push remota).
  cuotaPendiente('CUOTA_PENDIENTE'),

  /// Las visitas de mañana (push remota nocturna).
  agendaManana('AGENDA_MANANA');

  const TipoNotificacion(this.codigo);

  final String codigo;

  /// Inversa de [codigo]. Lanza `ArgumentError` con un valor desconocido: solo esta app escribe la
  /// tabla, así que sería un bug.
  static TipoNotificacion desdeCodigo(String codigo) => values.firstWhere(
    (t) => t.codigo == codigo,
    orElse: () => throw ArgumentError.value(codigo, 'codigo', 'tipo de notificación desconocido'),
  );
}

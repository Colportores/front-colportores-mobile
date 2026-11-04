/// De qué trata un aviso del centro de notificaciones (HU-NOT-005). [codigo] es el valor de la
/// columna `tipo` de `notificacion_historial`.
///
/// Los avisos que llegan por push (HU-NOT-003, S11; decisión de Cristian del 06/10, «Notif. S8») se
/// suman de a uno, cuando se acuerda su `type` con el servidor (ticket validado, zona asignada, cuota
/// pendiente…): cada uno es una línea nueva acá.
enum TipoNotificacion {
  /// El recordatorio local de una visita agendada (HU-NOT-002).
  recordatorioVisita('RECORDATORIO_VISITA'),

  /// El coordinador autorizó un pedido (push remota, HU-NOT-003).
  pedidoAutorizado('PEDIDO_AUTORIZADO');

  const TipoNotificacion(this.codigo);

  final String codigo;

  /// Inversa de [codigo]. Lanza `ArgumentError` con un valor desconocido: solo esta app escribe la
  /// tabla, así que sería un bug.
  static TipoNotificacion desdeCodigo(String codigo) => values.firstWhere(
    (t) => t.codigo == codigo,
    orElse: () => throw ArgumentError.value(codigo, 'codigo', 'tipo de notificación desconocido'),
  );
}

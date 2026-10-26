/// De qué trata un aviso del centro de notificaciones (HU-NOT-005). [codigo] es el valor de la
/// columna `tipo` de `notificacion_historial`.
///
/// Hoy hay un solo tipo: los avisos que llegan por push (pedido autorizado, ticket validado, zona
/// asignada, cuota pendiente) se suman con HU-NOT-003, en el S11 (decisión de Cristian del 06/10,
/// «Notif. S8»): cada uno es una línea nueva acá.
enum TipoNotificacion {
  /// El recordatorio local de una visita agendada (HU-NOT-002).
  recordatorioVisita('RECORDATORIO_VISITA');

  const TipoNotificacion(this.codigo);

  final String codigo;

  /// Inversa de [codigo]. Lanza `ArgumentError` con un valor desconocido: solo esta app escribe la
  /// tabla, así que sería un bug.
  static TipoNotificacion desdeCodigo(String codigo) => values.firstWhere(
    (t) => t.codigo == codigo,
    orElse: () => throw ArgumentError.value(codigo, 'codigo', 'tipo de notificación desconocido'),
  );
}

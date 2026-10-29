/// Qué se le pidió a la persona sobre las notificaciones (HU-NOT-001).
enum PedidoNotificaciones {
  /// Tocó «Ahora no» en el pedido del primer ingreso: el sistema todavía no le preguntó.
  ahoraNo,

  /// Se le mostró el diálogo del sistema. Si después las notificaciones siguen apagadas, desde la
  /// app ya no se pueden activar.
  sistema,
}

/// Lo que el teléfono recuerda del permiso de notificaciones, guardado fuera de la DB (almacén
/// seguro, `ClaveSegura.permisoNotificaciones` y `ClaveSegura.avisoNotificacionesCerrado`): si ya se
/// pidió (el pedido del primer ingreso no vuelve) y si se cerró el aviso de Hoy (no vuelve en esta
/// instalación).
///
/// Las operaciones se ejecutan **en el orden en que se piden**. Leer con el almacén roto lanza; anotar
/// nunca lanza (queda en el log): lo peor que pasa es que el pedido o el aviso se repitan.
abstract interface class PermisoNotificacionesRepository {
  /// Lo último que se anotó, o `null` si nunca se le pidió nada.
  Future<PedidoNotificaciones?> leerPedido();

  /// Anota [pedido]. `sistema` pisa a `ahoraNo`; `ahoraNo` nunca pisa a `sistema`.
  Future<void> anotarPedido(PedidoNotificaciones pedido);

  /// Si la persona cerró el aviso «Las notificaciones están apagadas».
  Future<bool> leerAvisoCerrado();

  Future<void> anotarAvisoCerrado();
}

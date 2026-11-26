import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/transferencia.dart';

/// DTO de [Transferencia]: la fila entera que se encola para el sync. [encabezadoAJson] y
/// [lineaAJson] usan los nombres de columna de `public.transferencia_stock` y `public.transferencia_item`
/// (`backend-supabase`, migraciones 0067 y 0139) y las fechas en ISO-8601 UTC.
///
/// El teléfono manda solo `id`, `origen_id`, `destino_id` y `estado` del encabezado (y `id`,
/// `transferencia_id`, `producto_id` y `cantidad` de la línea) más la auditoría: todo lo demás
/// (`solicitante_id`, `fecha_solicitud`, `numero`, `coordinador_id`, `monto_deuda`, `decidido_en`,
/// `motivo_rechazo`, `baja_a_*`, `precio_unitario`) lo pone el servidor y el push lo descartaría. Un test
/// fija la lista exacta de claves (también la de la cancelación, [cancelacionAJson]).
///
/// **Sin dato de ninguna persona más que ids opacos** (ADR-004).
abstract final class TransferenciaModel {
  static Map<String, Object?> encabezadoAJson(Transferencia t) => {
    'id': t.id,
    'origen_id': t.origenId,
    'destino_id': t.destinoId,
    'estado': codigoDelEstado(t.estado),
    ...auditoriaAJson(t.auditoria),
  };

  /// El update de la cancelación: solo `id` y `estado` (más la auditoría). El servidor da al teléfono
  /// `update (id, estado, created_at, deleted_at)` sobre `transferencia_stock` (migración 0148): subir
  /// `origen_id` o `destino_id` en el UPDATE se rechaza con 42501 aunque el valor no cambie. Si la cancelación
  /// se funde en un alta todavía no subida, el motor conserva `origen_id` y `destino_id` del alta.
  static Map<String, Object?> cancelacionAJson(Transferencia t) => {
    'id': t.id,
    'estado': codigoDelEstado(t.estado),
    ...auditoriaAJson(t.auditoria),
  };

  static Map<String, Object?> lineaAJson(LineaDeTransferencia l, Transferencia t) => {
    'id': l.id,
    'transferencia_id': t.id,
    'producto_id': l.productoId,
    'cantidad': l.cantidad,
    ...auditoriaAJson(t.auditoria),
  };

  /// El código que viaja al servidor. [EstadoDeTransferencia.autorizada] es `AUTORIZADO`.
  static String codigoDelEstado(EstadoDeTransferencia estado) => switch (estado) {
    EstadoDeTransferencia.porAutorizar => 'PENDIENTE_AUTORIZACION',
    EstadoDeTransferencia.autorizada => 'AUTORIZADO',
    EstadoDeTransferencia.rechazada => 'RECHAZADO',
    EstadoDeTransferencia.cancelada => 'CANCELADO',
  };

  /// El estado de un código del servidor. `EJECUTADO` (sin uso desde 0126) se lee como autorizada. Un
  /// código que esta versión no conoce se deja como «por autorizar»: la transferencia no desaparece, y la
  /// coordinadora todavía no dijo que sí.
  static EstadoDeTransferencia estadoDesdeCodigo(String codigo) => switch (codigo) {
    'AUTORIZADO' || 'EJECUTADO' => EstadoDeTransferencia.autorizada,
    'RECHAZADO' => EstadoDeTransferencia.rechazada,
    'CANCELADO' => EstadoDeTransferencia.cancelada,
    _ => EstadoDeTransferencia.porAutorizar,
  };
}

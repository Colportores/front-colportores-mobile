import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/entrega.dart';

/// DTO de [Entrega]: la fila entera que se encola para el sync. [toJson] usa los nombres de columna de
/// `public.entrega` (`backend-supabase`, migraciones 0001 y 0068) y las fechas en ISO-8601 UTC. No lleva
/// `stock_inconsistente` (0118): la pone el servidor y el push la descarta. Un test fija la lista
/// exacta de claves.
///
/// **Sin dato del cliente** (ADR-004): `venta_id` y `producto_id` son ids opacos.
abstract final class EntregaModel {
  static Map<String, Object?> toJson(Entrega entrega) => {
    'id': entrega.id,
    'venta_id': entrega.ventaId,
    'producto_id': entrega.productoId,
    'cantidad': entrega.cantidad,
    'fecha_prevista': entrega.fechaPrevista?.toIso8601String(),
    'fecha_entrega': entrega.fechaEntrega?.toIso8601String(),
    'pendiente': entrega.pendiente,
    ...auditoriaAJson(entrega.auditoria),
  };

  /// La fila de `entrega` de la DB local como entidad.
  static Entrega desdeFila(EntregaFila fila) => Entrega(
    id: fila.id,
    ventaId: fila.ventaId,
    productoId: fila.productoId,
    cantidad: fila.cantidad,
    pendiente: fila.pendiente,
    fechaPrevista: fila.fechaPrevista,
    fechaEntrega: fila.fechaEntrega,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );
}

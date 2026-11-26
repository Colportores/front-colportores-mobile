import '../../../../core/domain/entities/auditoria.dart';
import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/pedido.dart';

/// DTO de [Pedido]: lo que se encola para el sync. [encabezadoAJson] y [lineaAJson] usan los nombres de
/// columna de `public.pedido_casa_editora` y `public.pedido_item` (backend-supabase, migración 0124) y las
/// fechas en ISO-8601 UTC.
///
/// El teléfono manda solo `id` y `estado` del pedido (nace `PENDIENTE_AUTORIZACION`; al cancelar, `CANCELADO`)
/// y `id`, `pedido_id`, `producto_id` y `cantidad` de cada línea, más la auditoría. Todo lo demás
/// (`colportor_id`, `coordinador_id`, `fecha_pedido`, `monto_total`, `origen`, `excede_limite`, `numero`,
/// `precio_unitario`…) lo pone el servidor y el push lo descartaría: **el precio de cada línea lo copia el
/// servidor del costo de la casa editora, nadie lo tipea**. Un test fija la lista exacta de claves.
abstract final class PedidoModel {
  static Map<String, Object?> encabezadoAJson(String id, EstadoDelPedido estado, Auditoria a) => {
    'id': id,
    'estado': estado.codigo,
    ...auditoriaAJson(a),
  };

  static Map<String, Object?> lineaAJson(LineaDelPedido l, String pedidoId, Auditoria a) => {
    'id': l.id,
    'pedido_id': pedidoId,
    'producto_id': l.productoId,
    'cantidad': l.cantidad,
    ...auditoriaAJson(a),
  };
}

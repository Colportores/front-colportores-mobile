import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/componente_vendido.dart';
import '../../domain/entities/venta.dart';
import '../../domain/entities/venta_item.dart';

/// DTO de [Venta]: la fila entera que se encola para el sync. [toJson] usa los nombres de columna de
/// `public.venta` (`backend-supabase`, migraciones 0001 y 0071) y las fechas en ISO-8601 UTC. Un test
/// fija la lista exacta de claves contra las columnas de la tabla local.
///
/// **Sin dato del cliente** (ADR-004, R-VE05): `espacio_persona_id` es un id opaco. La única prosa
/// que sube es `motivo_monto_manual`, por decisión explícita de Cristian (23/10).
abstract final class VentaModel {
  /// [itemsEsperados] es cuántos renglones lleva la venta cuando se termina de armar (decisión de
  /// Cristian, 03/11, «Total arriba»; backend 0158, `venta.items_esperados`): con todos los ítems
  /// llegados el servidor exige el motivo del total cambiado a mano **en los dos sentidos**. Es una
  /// columna del push y no se guarda en el teléfono: sin ella (`null`, 0 o menos) el servidor aplica
  /// solo la regla de siempre, total por debajo de la suma.
  static Map<String, Object?> toJson(Venta venta, {int? itemsEsperados}) => {
    'id': venta.id,
    'espacio_persona_id': venta.espacioPersonaId,
    'numero_talonario': venta.numeroTalonario,
    'monto_total': venta.montoTotalCentavos,
    'fecha': venta.fecha.toIso8601String(),
    'colportor_id': venta.colportorId,
    'visita_id': venta.visitaId,
    'motivo_monto_manual': venta.motivoMontoManual,
    if (itemsEsperados != null && itemsEsperados >= 1) 'items_esperados': itemsEsperados,
    ...auditoriaAJson(venta.auditoria),
  };
}

/// DTO de [VentaItem]: la fila entera de `public.venta_item` (migraciones 0001, 0056 y 0071). Los
/// `componentes` suben como el arreglo `jsonb` que el servidor valida.
abstract final class VentaItemModel {
  static Map<String, Object?> toJson(VentaItem item) => {
    'id': item.id,
    'venta_id': item.ventaId,
    'producto_id': item.productoId,
    'coleccion_id': item.coleccionId,
    'cantidad': item.cantidad,
    'precio_unitario': item.precioUnitarioCentavos,
    'subtotal': item.subtotalCentavos,
    'componentes': componentesAJson(item.componentes),
    ...auditoriaAJson(item.auditoria),
  };

  /// `[{producto_id, cantidad}]`, o `null` en un producto suelto.
  static List<Map<String, Object?>>? componentesAJson(List<ComponenteVendido>? componentes) =>
      componentes == null
      ? null
      : [
          for (final c in componentes) {'producto_id': c.productoId, 'cantidad': c.cantidad},
        ];

  static List<ComponenteVendido>? componentesDesdeJson(List<Object?>? json) => json == null
      ? null
      : [
          for (final c in json)
            ComponenteVendido(
              productoId: (c! as Map<String, Object?>)['producto_id']! as String,
              cantidad: ((c as Map<String, Object?>)['cantidad']! as num).toInt(),
            ),
        ];
}

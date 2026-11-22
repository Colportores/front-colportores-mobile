import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/misionero_dejado.dart';

/// El payload de sync de [MisioneroDejado]: la fila de `public.visita_misionero` (backend-supabase
/// 0160) con las fechas en ISO-8601 UTC. Sin `colportor_id`: lo fija el servidor desde el JWT.
abstract final class MisioneroDejadoModel {
  static Map<String, Object?> toJson(MisioneroDejado m) => {
    'id': m.id,
    'visita_id': m.visitaId,
    'producto_id': m.productoId,
    'cantidad': m.cantidad,
    ...auditoriaAJson(m.auditoria),
  };
}

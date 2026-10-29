import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/cobranza.dart';

/// DTO de [Cobranza]: la fila entera que se encola para el sync. [toJson] usa los nombres de columna
/// de `public.cobranza` (`backend-supabase`, migración 0001) y las fechas en ISO-8601 UTC. Un test
/// fija la lista exacta de claves.
///
/// **Sin dato del cliente** (ADR-004, R-CB03): `venta_id` es un id opaco.
abstract final class CobranzaModel {
  static Map<String, Object?> toJson(Cobranza cobro) => {
    'id': cobro.id,
    'venta_id': cobro.ventaId,
    'monto': cobro.montoCentavos,
    'medio': codigoDelMedio(cobro.medio),
    'fecha': cobro.fecha.toIso8601String(),
    'numero_cuota': cobro.numeroCuota,
    ...auditoriaAJson(cobro.auditoria),
  };

  static String codigoDelMedio(MedioCobranza medio) => switch (medio) {
    MedioCobranza.efectivo => 'EFECTIVO',
    MedioCobranza.tarjeta => 'TARJETA',
    MedioCobranza.transferencia => 'TRANSFERENCIA',
  };

  static MedioCobranza medioDesdeCodigo(String codigo) => switch (codigo) {
    'EFECTIVO' => MedioCobranza.efectivo,
    'TARJETA' => MedioCobranza.tarjeta,
    'TRANSFERENCIA' => MedioCobranza.transferencia,
    _ => throw ArgumentError('Medio de cobro desconocido: $codigo'),
  };
}

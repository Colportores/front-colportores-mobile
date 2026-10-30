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
    'tarjeta_tipo': cobro.tarjetaTipo == null ? null : codigoDelTipoDeTarjeta(cobro.tarjetaTipo!),
    'tarjeta_marca': cobro.tarjetaMarca,
    'numero_aprobacion': cobro.numeroAprobacion,
    'referencia_transferencia': cobro.referenciaTransferencia,
    'banco_origen': cobro.bancoOrigen,
    // La marca de anulado sube con la fecha y el motivo de la lista; lo que se escribe con «Otro» no
    // (decisión de Cristian, 23/10, «Anulación»).
    'anulado_at': cobro.anuladoAt?.toIso8601String(),
    'motivo_anulacion': cobro.motivoAnulacion?.codigo,
    ...auditoriaAJson(cobro.auditoria),
  };

  static String codigoDelMedio(MedioCobranza medio) => switch (medio) {
    MedioCobranza.efectivo => 'EFECTIVO',
    MedioCobranza.tarjeta => 'TARJETA',
    MedioCobranza.transferencia => 'TRANSFERENCIA',
  };

  static String codigoDelTipoDeTarjeta(TipoTarjeta tipo) => switch (tipo) {
    TipoTarjeta.debito => 'DEBITO',
    TipoTarjeta.credito => 'CREDITO',
  };

  /// El tipo de tarjeta de un código guardado; `null` si no hay o no se reconoce (un dato opcional
  /// nunca tumba la lectura del cobro).
  static TipoTarjeta? tipoDeTarjetaDesdeCodigo(String? codigo) => switch (codigo) {
    'DEBITO' => TipoTarjeta.debito,
    'CREDITO' => TipoTarjeta.credito,
    _ => null,
  };

  static MedioCobranza medioDesdeCodigo(String codigo) => switch (codigo) {
    'EFECTIVO' => MedioCobranza.efectivo,
    'TARJETA' => MedioCobranza.tarjeta,
    'TRANSFERENCIA' => MedioCobranza.transferencia,
    _ => throw ArgumentError('Medio de cobro desconocido: $codigo'),
  };
}

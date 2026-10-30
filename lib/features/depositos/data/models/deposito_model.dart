import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/deposito.dart';

/// DTO de [Deposito]: la fila entera que se encola para el sync. [toJson] usa los nombres de columna
/// de `public.deposito` (`backend-supabase`, migraciones 0067, 0114 y 0122) y las fechas en
/// ISO-8601 UTC. No lleva `colportor_id` (lo fija el servidor con el JWT) ni la validación ni el
/// rechazo (los pone el servidor): el push los descartaría. Un test fija la lista exacta de claves.
///
/// **Sin dato de ninguna persona** (ADR-004): no hay cobros ni clientes; `ticket_id` y `campania_id`
/// son ids opacos.
abstract final class DepositoModel {
  static Map<String, Object?> toJson(Deposito deposito) => {
    'id': deposito.id,
    'monto': deposito.montoCentavos,
    'fecha': deposito.fecha.toIso8601String(),
    'destino': codigoDelDestino(deposito.destino),
    'concepto': codigoDelConcepto(deposito.concepto),
    'campania_id': deposito.campaniaId,
    'ticket_id': deposito.ticketId,
    ...auditoriaAJson(deposito.auditoria),
  };

  static String codigoDelDestino(DestinoDeDeposito destino) => switch (destino) {
    DestinoDeDeposito.banco => 'BANCO',
    DestinoDeDeposito.oficina => 'OFICINA',
    DestinoDeDeposito.retiroCoordinador => 'RETIRO_COORDINADOR',
  };

  static DestinoDeDeposito destinoDesdeCodigo(String codigo) => switch (codigo) {
    'BANCO' => DestinoDeDeposito.banco,
    'OFICINA' => DestinoDeDeposito.oficina,
    'RETIRO_COORDINADOR' => DestinoDeDeposito.retiroCoordinador,
    _ => throw ArgumentError('Destino de depósito desconocido: $codigo'),
  };

  static String codigoDelConcepto(ConceptoDeDeposito concepto) => switch (concepto) {
    ConceptoDeDeposito.casaEditora => 'CASA_EDITORA',
    ConceptoDeDeposito.alquiler => 'ALQUILER',
  };

  static ConceptoDeDeposito conceptoDesdeCodigo(String codigo) => switch (codigo) {
    'CASA_EDITORA' => ConceptoDeDeposito.casaEditora,
    'ALQUILER' => ConceptoDeDeposito.alquiler,
    _ => throw ArgumentError('Concepto de depósito desconocido: $codigo'),
  };
}

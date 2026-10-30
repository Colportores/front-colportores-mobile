import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/ticket.dart';

/// DTO de [Ticket]: la fila que se encola para el sync. [toJson] usa los nombres de columna de
/// `public.ticket` (`backend-supabase`, migraciones 0067 y 0113) y las fechas en ISO-8601 UTC.
///
/// **No lleva las columnas del servidor** (`usuario_id`, `subido_en`, `estado`, `revisado_por`,
/// `revisado_en`, `motivo_rechazo`, `campania_validadora_id`): el push las descarta en silencio y un
/// cliente que las manda con otro valor recibe `42501`. Un test fija la lista exacta de claves.
///
/// **No lleva la foto**: viaja por un enlace firmado y solo su ruta (`url_cloud`) va en la fila, una
/// vez subida. **Sin dato del cliente** (ADR-004).
abstract final class TicketModel {
  static Map<String, Object?> toJson(Ticket ticket) => {
    'id': ticket.id,
    'tipo': codigoDelTipo(ticket.tipo),
    'url_cloud': ticket.urlCloud,
    'monto': ticket.montoCentavos,
    'fecha': ticket.fecha.toIso8601String(),
    'numero_autorizacion': ticket.numeroAutorizacion,
    'tarjeta_tipo': ticket.tarjetaTipo == null ? null : codigoDeLaTarjeta(ticket.tarjetaTipo!),
    'tarjeta_marca': ticket.tarjetaMarca,
    ...auditoriaAJson(ticket.auditoria),
  };

  static String codigoDelTipo(TipoDeTicket tipo) => switch (tipo) {
    TipoDeTicket.cobroTarjeta => 'COBRO_TARJETA',
    TipoDeTicket.deposito => 'DEPOSITO',
    TipoDeTicket.otro => 'OTRO',
  };

  static TipoDeTicket tipoDesdeCodigo(String codigo) => switch (codigo) {
    'COBRO_TARJETA' => TipoDeTicket.cobroTarjeta,
    'DEPOSITO' => TipoDeTicket.deposito,
    'OTRO' => TipoDeTicket.otro,
    _ => throw ArgumentError('Tipo de ticket desconocido: $codigo'),
  };

  static String codigoDeLaTarjeta(TipoDeTarjeta tipo) => switch (tipo) {
    TipoDeTarjeta.credito => 'CREDITO',
    TipoDeTarjeta.debito => 'DEBITO',
  };

  /// El tipo de tarjeta de un código guardado; `null` si no hay o no se reconoce (un dato opcional
  /// nunca tumba la lectura del ticket).
  static TipoDeTarjeta? tarjetaDesdeCodigo(String? codigo) => switch (codigo) {
    'CREDITO' => TipoDeTarjeta.credito,
    'DEBITO' => TipoDeTarjeta.debito,
    _ => null,
  };

  static String codigoDelEstado(EstadoDeTicket estado) => switch (estado) {
    EstadoDeTicket.pendiente => 'PENDIENTE',
    EstadoDeTicket.validado => 'VALIDADO',
    EstadoDeTicket.rechazado => 'RECHAZADO',
  };

  /// El estado de un código guardado; un código que no se reconoce se lee como pendiente.
  static EstadoDeTicket estadoDesdeCodigo(String codigo) => switch (codigo) {
    'VALIDADO' => EstadoDeTicket.validado,
    'RECHAZADO' => EstadoDeTicket.rechazado,
    _ => EstadoDeTicket.pendiente,
  };

  static String codigoDeLaSubida(EstadoDeSubida estado) => switch (estado) {
    EstadoDeSubida.pendiente => 'PENDIENTE',
    EstadoDeSubida.subida => 'SUBIDA',
    EstadoDeSubida.rechazada => 'RECHAZADA',
  };

  static EstadoDeSubida subidaDesdeCodigo(String codigo) => switch (codigo) {
    'SUBIDA' => EstadoDeSubida.subida,
    'RECHAZADA' => EstadoDeSubida.rechazada,
    _ => EstadoDeSubida.pendiente,
  };
}

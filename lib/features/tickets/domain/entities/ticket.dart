import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// De qué es el ticket (`ticket.tipo`): el de un cobro con tarjeta, el de un depósito en el banco o en
/// la oficina (HU-CTA-004) u otro comprobante.
enum TipoDeTicket { cobroTarjeta, deposito, otro }

/// La tarjeta del cobro: crédito o débito (`ticket.tarjeta_tipo`).
enum TipoDeTarjeta { credito, debito }

/// Cómo está el ticket para el coordinador (`ticket.estado`). Lo pone el servidor: el teléfono lo
/// crea siempre [pendiente] y lo ve cambiar cuando baja la fila.
enum EstadoDeTicket { pendiente, validado, rechazado }

/// El ticket que carga el colportor (HU-COB-007): la foto del comprobante y sus datos. Es la fila de
/// `public.ticket` (backend-supabase 0067, 0113 y 0146).
///
/// **Sin dato del cliente**: la foto va a un bucket privado y la fila lleva solo montos, una fecha, el
/// número de autorización y la tarjeta. La foto no viaja en la fila: [urlCloud] guarda su ruta en el
/// bucket (`<usuario_id>/<ticket_id>.<ext>`) y queda vacía hasta que la foto sube.
///
/// Las columnas del servidor ([usuarioId], [subidoEn], [estado], [revisadoPor], [revisadoEn],
/// [motivoRechazo] y [campaniaValidadoraId]) las escribe solo el servidor: el teléfono las crea vacías
/// y las ve cambiar con el pull.
final class Ticket extends Equatable {
  const Ticket({
    required this.id,
    required this.tipo,
    required this.montoCentavos,
    required this.fecha,
    required this.auditoria,
    this.numeroAutorizacion,
    this.tarjetaTipo,
    this.tarjetaMarca,
    this.urlCloud,
    this.estado = EstadoDeTicket.pendiente,
    this.motivoRechazo,
    this.campaniaValidadoraId,
    this.usuarioId,
    this.subidoEn,
    this.revisadoPor,
    this.revisadoEn,
  });

  final String id;
  final TipoDeTicket tipo;

  /// Lo que dice el ticket, en centavos; siempre mayor que cero.
  final int montoCentavos;

  /// La fecha del ticket; no es futura (el día de Montevideo).
  final DateTime fecha;

  /// El número de autorización (1 a 40 caracteres): obligatorio en el ticket de un cobro con tarjeta;
  /// en el de un depósito es el número de operación del banco (opcional).
  final String? numeroAutorizacion;

  /// Crédito o débito: obligatorio en el ticket de un cobro con tarjeta.
  final TipoDeTarjeta? tarjetaTipo;

  /// «Cuál» tarjeta (Visa, Master…, 1 a 40 caracteres): opcional hasta que el canvas lo dibuje.
  final String? tarjetaMarca;

  /// La ruta de la foto en el bucket; `null` hasta que la foto sube (y de nuevo `null` cuando el
  /// bucket la borra a los 4 meses).
  final String? urlCloud;

  final EstadoDeTicket estado;
  final String? motivoRechazo;

  /// La campaña cuya coordinadora lo valida; `null` = lo revisa Administración (backend 0146).
  final String? campaniaValidadoraId;

  final String? usuarioId;
  final DateTime? subidoEn;
  final String? revisadoPor;
  final DateTime? revisadoEn;

  final Auditoria auditoria;

  /// La foto ya está en el bucket.
  bool get fotoSubida => urlCloud != null;

  /// La fila ya llegó al servidor y volvió con sus datos (`subido_en` lo pone el servidor). Hasta
  /// entonces el teléfono no sabe quién lo valida: `campaniaValidadoraId` vacío no quiere decir
  /// «Administración», quiere decir «todavía no se sabe».
  bool get llegoAlServidor => subidoEn != null;

  /// Lo valida Administración (el servidor no encontró una campaña que lo valide, «Ticket libre»,
  /// backend-supabase#200 y #209). Solo se afirma con el dato que mandó el servidor.
  bool get loRevisaAdministracion => llegoAlServidor && campaniaValidadoraId == null;

  Ticket copyWith({String? urlCloud, Auditoria? auditoria}) => Ticket(
    id: id,
    tipo: tipo,
    montoCentavos: montoCentavos,
    fecha: fecha,
    auditoria: auditoria ?? this.auditoria,
    numeroAutorizacion: numeroAutorizacion,
    tarjetaTipo: tarjetaTipo,
    tarjetaMarca: tarjetaMarca,
    urlCloud: urlCloud ?? this.urlCloud,
    estado: estado,
    motivoRechazo: motivoRechazo,
    campaniaValidadoraId: campaniaValidadoraId,
    usuarioId: usuarioId,
    subidoEn: subidoEn,
    revisadoPor: revisadoPor,
    revisadoEn: revisadoEn,
  );

  @override
  List<Object?> get props => [
    id,
    tipo,
    montoCentavos,
    fecha,
    numeroAutorizacion,
    tarjetaTipo,
    tarjetaMarca,
    urlCloud,
    estado,
    motivoRechazo,
    campaniaValidadoraId,
    usuarioId,
    subidoEn,
    revisadoPor,
    revisadoEn,
    auditoria,
  ];
}

/// Tipos de imagen que acepta el servidor (`foto-ticket`): JPEG, PNG o WebP.
enum TipoDeImagen {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp');

  const TipoDeImagen(this.mime, this.extension);

  /// El `Content-Type` que firma el enlace de subida.
  final String mime;

  /// La extensión de la ruta del objeto (`<usuario_id>/<ticket_id>.<extension>`).
  final String extension;

  static TipoDeImagen? desdeMime(String mime) {
    for (final t in values) {
      if (t.mime == mime) return t;
    }
    return null;
  }
}

/// Cómo va la subida de la foto de un ticket.
enum EstadoDeSubida {
  /// Falta subirla (sin red, o el ticket todavía no llegó al servidor).
  pendiente,

  /// Está en el bucket y la ruta ya se guardó en el ticket.
  subida,

  /// El servidor la rechazó y reintentar no la arregla (más de 2 MiB, tipo de imagen que no acepta).
  rechazada,
}

/// La copia local de la foto de un ticket: lo que queda en el teléfono. Es **solo del teléfono**:
/// no sube nunca por el motor (la foto va por un enlace firmado) y se puede borrar sin tocar la nube
/// (supuesto S41).
final class FotoLocalDeTicket extends Equatable {
  const FotoLocalDeTicket({
    required this.ticketId,
    required this.tipoDeImagen,
    required this.bytes,
    required this.estado,
    required this.creadaEn,
    this.rutaLocal,
    this.intentos = 0,
    this.ultimoError,
  });

  final String ticketId;
  final TipoDeImagen tipoDeImagen;

  /// El tamaño de la foto comprimida, en bytes (lo que firma el enlace de subida).
  final int bytes;
  final EstadoDeSubida estado;
  final DateTime creadaEn;

  /// Dónde está el archivo en el teléfono; `null` si el colportor borró la copia local.
  final String? rutaLocal;

  /// Cuántas veces se intentó subirla.
  final int intentos;

  /// El código del último error de la subida (`foto_ya_subida`, `red`…), sin texto del servidor.
  final String? ultimoError;

  bool get hayCopiaLocal => rutaLocal != null;

  FotoLocalDeTicket copyWith({
    EstadoDeSubida? estado,
    int? intentos,
    Object? ultimoError = _sin,
    Object? rutaLocal = _sin,
  }) => FotoLocalDeTicket(
    ticketId: ticketId,
    tipoDeImagen: tipoDeImagen,
    bytes: bytes,
    estado: estado ?? this.estado,
    creadaEn: creadaEn,
    rutaLocal: identical(rutaLocal, _sin) ? this.rutaLocal : rutaLocal as String?,
    intentos: intentos ?? this.intentos,
    ultimoError: identical(ultimoError, _sin) ? this.ultimoError : ultimoError as String?,
  );

  @override
  List<Object?> get props => [
    ticketId,
    tipoDeImagen,
    bytes,
    estado,
    creadaEn,
    rutaLocal,
    intentos,
    ultimoError,
  ];
}

const Object _sin = Object();

/// El ticket guardado con su foto local.
final class TicketRegistrado extends Equatable {
  const TicketRegistrado({required this.ticket, required this.foto, this.yaEstaba = false});

  final Ticket ticket;
  final FotoLocalDeTicket foto;

  /// Ya había un ticket con ese `id` (un doble toque o un reintento): no se escribió ni se encoló
  /// nada de nuevo.
  final bool yaEstaba;

  @override
  List<Object?> get props => [ticket, foto, yaEstaba];
}

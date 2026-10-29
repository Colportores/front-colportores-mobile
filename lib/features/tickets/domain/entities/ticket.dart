import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../cobranzas/domain/entities/cobranza.dart' show TipoTarjeta;

/// Para qué es el comprobante (`ticket.tipo`). Hoy la app solo carga el de un cobro con tarjeta
/// (HU-COB-007); el de un depósito llega con HU-CTA-004.
enum TipoDeTicket { cobroTarjeta, deposito, otro }

/// Cómo va el ticket en la revisión del coordinador (`ticket.estado`). Lo pone el servidor: un
/// ticket nuevo nace [pendiente] y baja con el pull.
enum EstadoDeTicket { pendiente, validado, rechazado }

/// El comprobante del cobro con tarjeta (HU-COB-007, esquema-datos.md §`ticket`): la foto y los datos
/// que el colportor carga (fecha, número de autorización, tarjeta y monto). Sube por el motor de
/// sync; la foto **no** viaja por el motor (ver [FotoDeTicket]).
///
/// **Sin dato del cliente** (R-CB03): ni el nombre ni la persona del cobro.
class Ticket extends Equatable {
  Ticket({
    required this.id,
    this.tipo = TipoDeTicket.cobroTarjeta,
    this.montoCentavos,
    DateTime? fecha,
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
    required this.auditoria,
  }) : fecha = fecha?.toUtc();

  final String id;
  final TipoDeTicket tipo;

  /// En centavos, mayor que cero (como el dinero de toda la app).
  final int? montoCentavos;

  /// El día del ticket (no futuro, día de Montevideo), siempre en UTC.
  final DateTime? fecha;

  /// El número de autorización del POS: obligatorio en el ticket de un cobro con tarjeta, 1 a 40
  /// caracteres.
  final String? numeroAutorizacion;

  /// Crédito o débito: obligatorio en el ticket de un cobro con tarjeta.
  final TipoTarjeta? tarjetaTipo;

  /// «cuál»: la marca de la tarjeta. Opcional.
  final String? tarjetaMarca;

  /// La **ruta** de la foto en el bucket (`<usuario_id>/<ticket_id>.<ext>`), no una URL. `null` hasta
  /// que se sube la foto, o después de los 4 meses (RF-CO08A).
  final String? urlCloud;

  final EstadoDeTicket estado;
  final String? motivoRechazo;

  /// La campaña cuya coordinadora lo valida; `null` = lo revisa Administración (backend 0146). Lo
  /// escribe el servidor: llega con el pull, nunca lo manda el teléfono.
  final String? campaniaValidadoraId;

  /// De quién es (lo pone el servidor desde el JWT).
  final String? usuarioId;

  /// Cuándo llegó al servidor (reloj del servidor); `null` mientras el ticket solo está en el teléfono.
  final DateTime? subidoEn;
  final String? revisadoPor;
  final DateTime? revisadoEn;
  final Auditoria auditoria;

  /// El servidor ya tiene la fila y su respuesta bajó: los datos del servidor (campaña que valida,
  /// estado) valen. Mientras `subidoEn` sea `null` el ticket solo está en el teléfono.
  bool get llegoAlServidor => subidoEn != null;

  @override
  bool? get stringify => false;

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

/// Cómo va la subida de la foto de un ticket. Es estado **local** del teléfono.
enum EstadoDeSubida {
  /// Está en el teléfono y todavía no subió (sin conexión, o falta reintentar): el `TICKET_PENDING_UPLOAD`
  /// de la HU.
  pendiente,

  /// Subió: el ticket ya tiene su ruta en [Ticket.urlCloud].
  subida,

  /// El servidor no aceptó la foto (una falla que no es de conexión): se reintenta, pero la colportora lo
  /// ve (29C·06).
  conError,
}

/// La foto de un ticket guardada en el teléfono (tabla local `ticket_foto`, nunca sube por sync): el
/// archivo comprimido, qué tan lejos llegó la subida y si la colportora ya borró su copia.
class FotoDeTicket extends Equatable {
  const FotoDeTicket({
    required this.ticketId,
    required this.rutaLocal,
    required this.tipoDeImagen,
    required this.bytes,
    required this.estado,
    this.intentos = 0,
    this.motivoDelError,
    required this.actualizadaEn,
  });

  final String ticketId;

  /// El archivo de la copia local; `null` si la colportora la borró (29C·08), cosa que solo puede pasar
  /// con la foto ya [EstadoDeSubida.subida].
  final String? rutaLocal;

  /// `image/jpeg`, `image/png` o `image/webp`.
  final String tipoDeImagen;
  final int bytes;
  final EstadoDeSubida estado;
  final int intentos;

  /// El código de la última falla (para el log y para decidir el aviso), nunca texto del usuario.
  final String? motivoDelError;
  final DateTime actualizadaEn;

  bool get tieneCopiaLocal => rutaLocal != null;

  /// La extensión que lleva la ruta en el bucket.
  String get extension => ExtensionesDeImagen.deTipo(tipoDeImagen) ?? 'jpg';

  @override
  List<Object?> get props => [
    ticketId,
    rutaLocal,
    tipoDeImagen,
    bytes,
    estado,
    intentos,
    motivoDelError,
    actualizadaEn,
  ];
}

/// Los tipos de imagen que acepta el servidor (backend `foto-ticket`): JPG, PNG o WebP, hasta 2 MiB.
abstract final class ExtensionesDeImagen {
  static const jpeg = 'image/jpeg';
  static const png = 'image/png';
  static const webp = 'image/webp';

  /// El tope del servidor, en bytes (2 MiB).
  static const topeBytes = 2 * 1024 * 1024;

  static String? deTipo(String tipo) => switch (tipo) {
    jpeg => 'jpg',
    png => 'png',
    webp => 'webp',
    _ => null,
  };
}

/// Un ticket con la foto que tiene en este teléfono (si la tiene).
class TicketConFoto extends Equatable {
  const TicketConFoto({required this.ticket, this.foto});

  final Ticket ticket;
  final FotoDeTicket? foto;

  /// La foto está en el teléfono esperando subir (sin conexión o con error): lo que la HU llama
  /// «ticket_pendiente» del cobro.
  bool get fotoPendiente => foto != null && foto!.estado != EstadoDeSubida.subida;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [ticket, foto];
}

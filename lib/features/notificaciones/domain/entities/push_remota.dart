import 'package:equatable/equatable.dart';

import 'tipo_notificacion.dart';

/// Los tipos de push remota que la app sabe leer (HU-NOT-003, «Payload remoto: tipo de evento +
/// UUIDs relevantes»). [codigo] es el `type` del payload y [claveId] el campo con el UUID que lo
/// acompaña.
///
/// Hoy hay uno: el único que la HU escribe con su payload literal. Los demás (ticket validado o
/// rechazado, asignación a campaña, cuota pendiente, agenda de mañana) esperan a que se acuerde su
/// `type` con el servidor (pendiente del orquestador): cada uno es una línea nueva acá, con su texto
/// en [TextosPushRemota] y su [TipoNotificacion].
enum TipoPushRemota {
  /// El coordinador autorizó un pedido de la colportora: `{type: "pedido_autorizado", pedido_id}`.
  pedidoAutorizado(
    codigo: 'pedido_autorizado',
    claveId: 'pedido_id',
    tipoDeAviso: TipoNotificacion.pedidoAutorizado,
  );

  const TipoPushRemota({required this.codigo, required this.claveId, required this.tipoDeAviso});

  final String codigo;
  final String claveId;

  /// Cómo se guarda en el historial.
  final TipoNotificacion tipoDeAviso;

  /// `null` si [codigo] no es de un tipo conocido (una versión de la app más vieja que el servidor).
  static TipoPushRemota? desdeCodigo(String codigo) {
    for (final tipo in values) {
      if (tipo.codigo == codigo) return tipo;
    }
    return null;
  }
}

/// Una push remota ya leída y validada: de qué evento se trata y a qué fila apunta. Nunca trae texto
/// de la persona (R-NO02): el texto del aviso lo arma la app.
class PushRemota extends Equatable {
  const PushRemota({required this.tipo, required this.eventoId, required this.entidadId});

  final TipoPushRemota tipo;

  /// Identifica el evento: el mismo [eventoId] no genera dos avisos (idempotencia).
  final String eventoId;

  /// El UUID de la fila a la que apunta (el pedido, para `pedido_autorizado`).
  final String entidadId;

  @override
  List<Object?> get props => [tipo, eventoId, entidadId];
}

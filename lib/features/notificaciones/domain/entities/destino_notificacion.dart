import 'package:equatable/equatable.dart';

/// A dónde lleva tocar un aviso: el enlace interno de la notificación original (R-NO05).
///
/// Es solo un identificador (`agenda/<uuid>`), nunca un dato del cliente. [enlace] es lo que se
/// guarda en `notificacion_historial.destino`.
sealed class DestinoNotificacion extends Equatable {
  const DestinoNotificacion();

  /// El texto que se guarda: `agenda/<uuid>`.
  String get enlace;

  /// Inversa de [enlace]. `null` si [enlace] es `null`, está vacío o no es de un destino conocido:
  /// el aviso se muestra igual, solo que tocarlo no lleva a ningún lado.
  static DestinoNotificacion? desdeEnlace(String? enlace) {
    if (enlace == null) return null;
    const prefijoAgenda = 'agenda/';
    if (enlace.startsWith(prefijoAgenda) && enlace.length > prefijoAgenda.length) {
      return DestinoAgenda(enlace.substring(prefijoAgenda.length));
    }
    return null;
  }
}

/// El detalle de una agenda (vista 23, 23C·01).
final class DestinoAgenda extends DestinoNotificacion {
  const DestinoAgenda(this.agendaId);

  final String agendaId;

  @override
  String get enlace => 'agenda/$agendaId';

  @override
  List<Object?> get props => [agendaId];
}

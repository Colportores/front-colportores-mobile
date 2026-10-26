import 'package:equatable/equatable.dart';

/// Cómo están las notificaciones de la app en este teléfono (HU-NOT-001, vista 24).
enum EstadoPermisoNotificaciones {
  /// Activadas: los recordatorios ya funcionan.
  activadas,

  /// Apagadas, y el sistema todavía puede mostrar su diálogo: nunca se lo mostró (tocó «Ahora no», o
  /// el teléfono es de antes del Android 13 y las apagó en los ajustes sin que la app lo pida).
  /// Desde la app se pueden activar («Activar»).
  sinPedir,

  /// Apagadas, y desde la app ya no se pueden activar (24A·06): el sistema ya contestó que no, o las
  /// apagó la persona en los ajustes. Solo se activan en los ajustes del teléfono.
  bloqueadas,
}

/// Lo que la app sabe de las notificaciones de este teléfono: el estado del sistema, si la persona ya
/// contestó el pedido del primer ingreso y si cerró el aviso de Hoy (24A·03).
final class EstadoNotificaciones extends Equatable {
  const EstadoNotificaciones({
    required this.permiso,
    required this.pedidoRespondido,
    required this.avisoCerrado,
  });

  final EstadoPermisoNotificaciones permiso;

  /// Ya vio el pedido del primer ingreso y lo contestó («Activar» o «Ahora no»).
  final bool pedidoRespondido;

  /// Cerró con la ✕ el aviso «Notificaciones desactivadas»: no vuelve en esta instalación.
  final bool avisoCerrado;

  bool get activadas => permiso == EstadoPermisoNotificaciones.activadas;

  /// El primer ingreso muestra el pedido (24A·01) mientras la persona no lo contestó y las
  /// notificaciones sigan apagadas. Con las notificaciones ya activadas no hay nada que pedir.
  bool get debePedir => !pedidoRespondido && !activadas;

  /// El aviso de Hoy (24A·03): contestó el pedido, siguen apagadas y no lo cerró.
  bool get mostrarAviso => pedidoRespondido && !activadas && !avisoCerrado;

  EstadoNotificaciones copyWith({
    EstadoPermisoNotificaciones? permiso,
    bool? pedidoRespondido,
    bool? avisoCerrado,
  }) => EstadoNotificaciones(
    permiso: permiso ?? this.permiso,
    pedidoRespondido: pedidoRespondido ?? this.pedidoRespondido,
    avisoCerrado: avisoCerrado ?? this.avisoCerrado,
  );

  @override
  List<Object?> get props => [permiso, pedidoRespondido, avisoCerrado];
}

/// Cómo terminó «Activar».
enum ResultadoActivacion {
  /// La persona dio el permiso.
  activadas,

  /// El sistema contestó que no (la persona tocó «No permitir», o el sistema ya no deja preguntar).
  noConcedido,

  /// No se pudo pedir el permiso (falló la plataforma): se puede reintentar.
  fallo,
}

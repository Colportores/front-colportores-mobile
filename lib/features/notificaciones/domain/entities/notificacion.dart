import 'package:equatable/equatable.dart';

import '../../../../core/domain/instante.dart';
import 'destino_notificacion.dart';
import 'tipo_notificacion.dart';

/// Un aviso guardado en el historial del teléfono (HU-NOT-005, tabla local `notificacion_historial`).
///
/// [titulo] y [detalle] son el texto que se le mostró a la persona: la dirección y el tipo, **nunca el
/// nombre ni los datos del cliente** (R-NO02). [id] lo pone quien lo registra, y es lo que hace
/// idempotente el registro: el mismo aviso registrado dos veces queda una sola vez.
///
/// Los instantes se guardan en UTC y al milisegundo ([instanteMs]), como toda fecha de la DB local.
class Notificacion extends Equatable {
  Notificacion({
    required this.id,
    required this.tipo,
    required this.titulo,
    this.detalle,
    this.destino,
    required DateTime recibidaEn,
    DateTime? leidaEn,
  }) : recibidaEn = instanteMs(recibidaEn),
       leidaEn = leidaEn == null ? null : instanteMs(leidaEn);

  final String id;
  final TipoNotificacion tipo;
  final String titulo;

  /// La segunda línea (la dirección, por ejemplo), o `null`.
  final String? detalle;

  /// A dónde lleva tocarla, o `null` si no lleva a ningún lado.
  final DestinoNotificacion? destino;

  /// Cuándo llegó (o cuándo tenía que sonar, si el teléfono no pudo contarlo antes).
  final DateTime recibidaEn;

  /// Cuándo se marcó como leída; `null` = todavía no.
  final DateTime? leidaEn;

  bool get leida => leidaEn != null;

  @override
  List<Object?> get props => [id, tipo, titulo, detalle, destino, recibidaEn, leidaEn];

  /// El texto del aviso puede traer la dirección de una visita: no va a ningún log (convenciones
  /// §7.5).
  @override
  bool? get stringify => false;
}

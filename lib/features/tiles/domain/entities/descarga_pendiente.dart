import 'package:equatable/equatable.dart';

import 'paquete_tiles.dart';

/// Una descarga que el colportor pidió y todavía no terminó (HU-SYNC-010, «La descarga sigue
/// después de cerrar la app», #300). La app la anota en el teléfono para retomarla al volver a
/// abrirse, aunque la haya cerrado el colportor o Android.
///
/// Guarda el [paquete] **con el que empezó** (su dirección, su tamaño y su huella, no lo que el
/// catálogo diga hoy): así se sigue sobre el mismo archivo y desde lo que ya bajó, aunque el
/// catálogo ya traiga una versión nueva. También cubre el pedido que quedó en cola y nunca llegó a
/// arrancar (sin conexión).
final class DescargaPendiente extends Equatable {
  const DescargaPendiente({
    required this.paquete,
    required this.anotadaEn,
    this.permitirDatosMoviles = false,
    this.pausadaPorElColportor = false,
  });

  /// Cuánto se guarda una descarga sin terminar: lo mismo que el `.part` y que el archivo retirado
  /// del catálogo en el bucket (HU-SYNC-010, «Retomar un paquete que el catálogo ya retiró»).
  static const vigencia = Duration(days: 7);

  /// El paquete del catálogo con el que se empezó.
  final PaqueteTiles paquete;

  /// Cuándo se pidió: de ahí se cuentan los [vigencia] días. Un reintento o un reinicio no la
  /// renuevan; un pedido nuevo del colportor, sí.
  final DateTime anotadaEn;

  /// El colportor tocó «Descargar mapa»: ese toque es el permiso para usar datos móviles.
  final bool permitirDatosMoviles;

  /// El colportor la pausó él. Se anota (no se pierde lo que bajó) pero no se retoma sola al abrir
  /// la app: el uso de datos lo controla él.
  final bool pausadaPorElColportor;

  String get id => paquete.id;

  /// `true` si ya pasaron los [vigencia] días desde [anotadaEn].
  bool vencida(DateTime ahora) => ahora.difference(anotadaEn) >= vigencia;

  @override
  List<Object?> get props => [paquete, anotadaEn, permitirDatosMoviles, pausadaPorElColportor];
}

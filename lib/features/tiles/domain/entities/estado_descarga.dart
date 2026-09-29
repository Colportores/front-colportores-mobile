import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import 'paquete_tiles.dart';

/// Por qué quedó en pausa una descarga.
enum MotivoPausa {
  /// La pausó el colportor: sigue solo cuando él la reanuda.
  usuario,

  /// Se fue el Wi-Fi y no autorizó datos móviles: sigue sola cuando vuelve el Wi-Fi.
  sinWifi,

  /// Se cortó la red a mitad de la descarga: sigue sola cuando vuelve la conexión.
  sinConexion,
}

/// En qué está la descarga de un paquete (HU-SYNC-010). Es lo que va a mostrar la barra de
/// progreso de "Mapas offline"; la vista espera el diseño.
sealed class EstadoDescarga extends Equatable {
  const EstadoDescarga(this.paqueteId);

  final String paqueteId;

  @override
  List<Object?> get props => [paqueteId];
}

/// Bajando bytes. [recibidos] incluye lo que ya estaba en el `.part` de un intento anterior.
final class DescargaEnCurso extends EstadoDescarga {
  const DescargaEnCurso(super.paqueteId, {required this.recibidos, required this.total});

  final int recibidos;
  final int total;

  /// Entre 0 y 1, para la barra de progreso.
  double get progreso => total <= 0 ? 0 : (recibidos / total).clamp(0, 1).toDouble();

  @override
  List<Object?> get props => [...super.props, recibidos, total];
}

/// En pausa, con el `.part` guardado para seguir desde [recibidos] (HTTP Range).
final class DescargaPausada extends EstadoDescarga {
  const DescargaPausada(
    super.paqueteId, {
    required this.motivo,
    required this.recibidos,
    required this.total,
  });

  final MotivoPausa motivo;
  final int recibidos;
  final int total;

  /// `true` si sigue sola cuando vuelve la conexión; la pausa del colportor la levanta él.
  bool get sigueSola => motivo != MotivoPausa.usuario;

  @override
  List<Object?> get props => [...super.props, motivo, recibidos, total];
}

/// Terminó de bajar y se está validando el checksum.
final class DescargaVerificando extends EstadoDescarga {
  const DescargaVerificando(super.paqueteId);
}

/// Descargado, validado y registrado: el mapa ya lo puede usar sin red.
final class DescargaCompletada extends EstadoDescarga {
  DescargaCompletada(this.descargado) : super(descargado.paquete.id);

  final PaqueteDescargado descargado;

  @override
  List<Object?> get props => [...super.props, descargado];
}

/// No se pudo terminar. Si fue por checksum ([FailurePaqueteTilesCorrupto]) el `.part` ya se
/// borró y el próximo intento arranca de cero.
final class DescargaFallida extends EstadoDescarga {
  const DescargaFallida(super.paqueteId, this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [...super.props, failure];
}

/// El paquete se eliminó (y su descarga, si estaba a medias): no queda ni `.part` ni `.pmtiles`.
final class DescargaEliminada extends EstadoDescarga {
  const DescargaEliminada(super.paqueteId);
}

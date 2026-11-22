import 'package:equatable/equatable.dart';

/// El tramo de tiempo de «la campaña en curso» (HU-VIS-002): de [desde] (incluido) a [hasta]
/// (excluido), en UTC. Un lado en `null` está abierto: la campaña permanente no tiene fin, y sin
/// ninguna campaña en curso en el teléfono no se sabe ninguno de los dos.
class RangoDeCampania extends Equatable {
  const RangoDeCampania({this.desde, this.hasta});

  /// Sin campaña conocida: no se recorta nada (la agenda no esconde citas por no saber la campaña).
  static const sinLimite = RangoDeCampania();

  final DateTime? desde;
  final DateTime? hasta;

  @override
  List<Object?> get props => [desde, hasta];
}

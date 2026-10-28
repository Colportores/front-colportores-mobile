import 'package:equatable/equatable.dart';

import '../../../agenda/domain/entities/agenda.dart';
import '../../../mapa/domain/entities/color_house_status.dart';
import 'entrega.dart';

/// La entrega dejada para otra fecha, ya guardada (HU-VEN-003, «Entrega diferida»): lo pendiente de
/// la venta con su fecha prevista y la cita de esa fecha en la agenda.
final class EntregaDiferida extends Equatable {
  const EntregaDiferida({
    required this.entregas,
    required this.cita,
    this.direccion = '',
    this.colorDeLaCasa,
    this.yaEstaba = false,
    this.citaNueva = true,
  });

  /// Todas las filas vivas de la venta, las pendientes con la fecha prevista y las que ya se
  /// entregaron.
  final List<Entrega> entregas;

  /// La cita de la entrega en la agenda (`ENTREGA`, `PROGRAMADA`, con la venta y la entrega que la
  /// originan).
  final Agenda cita;

  /// La dirección de la casa para el aviso («Av. Italia 1234»); vacía si la ubicación no está en el
  /// teléfono.
  final String direccion;

  /// El color de la casa después de guardar (`house_status`); `null` si la casa quedó sin color o no
  /// está en el teléfono.
  final ColorHouseStatus? colorDeLaCasa;

  /// La venta ya tenía esa misma fecha y su cita (un doble toque o un reintento): no se escribió
  /// nada de nuevo.
  final bool yaEstaba;

  /// La cita se creó ahora. `false`: ya había una `PROGRAMADA` de esa venta y se la movió a la fecha
  /// nueva (o ya estaba en ella).
  final bool citaNueva;

  @override
  List<Object?> get props => [entregas, cita, direccion, colorDeLaCasa, yaEstaba, citaNueva];
}

/// Lo que dejó «Entregado hoy» (HU-VEN-003, «Cumplir entrega pendiente»).
final class EntregaCumplida extends Equatable {
  const EntregaCumplida({
    required this.entregas,
    required this.entregadas,
    this.cita,
    this.citaCumplida = false,
    this.citaConFechaNueva = false,
    this.direccion = '',
    this.colorDeLaCasa,
    this.yaEstaba = false,
  });

  /// Todas las filas vivas de la venta, como quedaron.
  final List<Entrega> entregas;

  /// Las filas que este «Entregado» pasó a entregadas (vacío si ya estaban: [yaEstaba]).
  final List<Entrega> entregadas;

  /// La cita `ENTREGA` de la venta como quedó, o `null` si no tenía una `PROGRAMADA` (la entrega salió
  /// de una entrega inmediata parcial o la cita se canceló a mano).
  final Agenda? cita;

  /// La cita pasó a `CUMPLIDA`: su aviso ya no tiene que sonar.
  final bool citaCumplida;

  /// Quedó algo pendiente con fecha nueva y la cita se movió a ella: su aviso hay que reprogramarlo.
  final bool citaConFechaNueva;

  /// La dirección de la casa para el aviso.
  final String direccion;

  /// El color de la casa después de guardar; `null` si quedó sin color o no está en el teléfono.
  final ColorHouseStatus? colorDeLaCasa;

  /// Lo pedido ya estaba entregado (un doble toque o un reintento): no se escribió nada de nuevo.
  final bool yaEstaba;

  /// Quedó algo por entregar.
  bool get quedaPendiente => entregas.any((e) => e.pendiente);

  @override
  List<Object?> get props => [
    entregas,
    entregadas,
    cita,
    citaCumplida,
    citaConFechaNueva,
    direccion,
    colorDeLaCasa,
    yaEstaba,
  ];
}

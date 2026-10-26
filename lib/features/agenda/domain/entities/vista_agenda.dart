import 'package:equatable/equatable.dart';

import 'item_agenda.dart';

/// Las agendas de un día, en orden cronológico (23B·01: «HOY · MIÉRCOLES 23»).
class DiaDeAgenda extends Equatable {
  const DiaDeAgenda({required this.dia, required this.items, required this.diasDesdeHoy});

  /// El día, a medianoche en hora local.
  final DateTime dia;

  /// Las agendas del día, de la más temprana a la más tardía.
  final List<ItemAgenda> items;

  /// 0 = hoy, 1 = mañana…
  final int diasDesdeHoy;

  bool get esHoy => diasDesdeHoy == 0;
  bool get esManana => diasDesdeHoy == 1;

  /// El conteo del día («Hoy (3)», HU-VIS-002).
  int get cantidad => items.length;

  @override
  List<Object?> get props => [dia, items, diasDesdeHoy];
}

/// Lo que la pantalla de la agenda dibuja: los días con agendas, agrupados.
class VistaAgenda extends Equatable {
  const VistaAgenda({required this.dias});

  static const vacia = VistaAgenda(dias: []);

  final List<DiaDeAgenda> dias;

  bool get estaVacia => dias.isEmpty;

  int get total => dias.fold(0, (suma, d) => suma + d.cantidad);

  @override
  List<Object?> get props => [dias];
}

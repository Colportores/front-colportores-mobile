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

/// Lo que la pantalla de la agenda dibuja: las atrasadas y, debajo, los días con agendas, agrupados.
class VistaAgenda extends Equatable {
  const VistaAgenda({
    required this.dias,
    this.atrasadas = const [],
    this.deCampania = false,
    this.hayMas = false,
  });

  static const vacia = VistaAgenda(dias: []);

  /// El grupo «ATRASADAS (N)» (P3, decisión de Cristian): las `PROGRAMADA` de días anteriores a hoy
  /// que siguen sin resultado, de la más antigua a la más reciente. Van arriba de «HOY».
  final List<ItemAgenda> atrasadas;

  final List<DiaDeAgenda> dias;

  /// Es la lista de **la campaña en curso** (un estado cerrado o «Todas»): los días van del más nuevo
  /// al más viejo y, como se pagina con «Ver más», sin el conteo de cada día (el último quedaría a
  /// medias).
  final bool deCampania;

  /// Quedan agendas de la campaña por mostrar: la pantalla ofrece «Ver más».
  final bool hayMas;

  bool get estaVacia => dias.isEmpty && atrasadas.isEmpty;

  int get total => atrasadas.length + dias.fold(0, (suma, d) => suma + d.cantidad);

  @override
  List<Object?> get props => [dias, atrasadas, deCampania, hayMas];
}

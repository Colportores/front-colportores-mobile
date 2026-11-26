import 'package:equatable/equatable.dart';

/// Un colportor de la misma campaña, al que se le puede pedir materiales (vista 40, 40A·02).
///
/// Solo lo que la pantalla muestra: el nombre y, si el servidor lo dice, dónde trabaja («Rivera»).
final class CompanieroDeCampania extends Equatable {
  const CompanieroDeCampania({required this.id, required this.nombre, this.lugar});

  /// UUID del usuario: lo que viaja en `origen_id`.
  final String id;

  final String nombre;

  /// Su ciudad o su zona, si el servidor la da.
  final String? lugar;

  @override
  List<Object?> get props => [id, nombre, lugar];
}

/// Los compañeros de la campaña en curso del colportor.
final class CompanierosDeCampania extends Equatable {
  const CompanierosDeCampania({required this.campania, required this.companieros});

  /// El nombre de la campaña («Primavera 2026»).
  final String campania;

  /// Los demás colportores de la campaña, sin quien pregunta; puede estar vacía (40A·09).
  final List<CompanieroDeCampania> companieros;

  /// El compañero [id], o `null` si no está en la lista.
  CompanieroDeCampania? por(String id) {
    for (final c in companieros) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  List<Object?> get props => [campania, companieros];
}

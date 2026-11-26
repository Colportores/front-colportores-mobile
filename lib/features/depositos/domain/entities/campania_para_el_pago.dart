import 'package:equatable/equatable.dart';

/// Una campaña a la que el colportor le puede pagar el alquiler (HU-CTA-007, decisión «Alq. campaña»):
/// una en la que está inscripto y que está en curso. Con dos, él elige a cuál paga.
final class CampaniaParaElPago extends Equatable {
  const CampaniaParaElPago({required this.id, required this.nombre});

  final String id;

  /// El nombre de la campaña, como lo ve el colportor («Primavera 2026»).
  final String nombre;

  @override
  List<Object?> get props => [id, nombre];
}

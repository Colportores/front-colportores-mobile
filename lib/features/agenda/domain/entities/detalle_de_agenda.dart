import 'package:equatable/equatable.dart';

import 'agenda.dart';
import 'visita.dart';

/// Una agenda con lo que el detalle (vista 23, 23C·01) necesita además de sus columnas: su nota
/// (local-only) y, si ya se cumplió o no se cumplió, la visita que la cerró.
///
/// **Lleva la nota** (dato personal): nunca debe salir en un log ni en un `toString`.
class DetalleDeAgenda extends Equatable {
  const DetalleDeAgenda({required this.agenda, this.nota, this.visita});

  final Agenda agenda;

  /// El texto de la nota de la agenda, o `null` si no tiene.
  final String? nota;

  /// La visita que cumplió (o no cumplió) la agenda (`agenda.visita_id`), si está en el teléfono.
  final Visita? visita;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [agenda, nota, visita];
}

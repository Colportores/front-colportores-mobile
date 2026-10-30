import '../../../../core/domain/entities/auditoria.dart';

/// Lo que tienen en común las notas que se ven en una tarjeta: de una persona (HU-UBI-012) o de un
/// lugar (vista 39, C·05). Las pantallas de notas dibujan la tarjeta, la fecha y las opciones con
/// esto, sin saber de qué es la nota.
///
/// **local-only — PII**: el texto nunca sale del teléfono ni va a los logs.
abstract interface class NotaDeTexto {
  String get id;

  String get texto;

  Auditoria get auditoria;

  /// La nota está dada de baja (`deleted_at`): sale de la lista y se ve en «Ver borradas».
  bool get estaBorrada;
}

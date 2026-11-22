import '../entities/nota_del_lugar.dart';

/// De dónde sale la nota más reciente de un lugar (la fila «NOTA DEL LUGAR» de la hoja de la casa,
/// vista 39 C·01). Local: las notas viven solo en el teléfono (ADR-004).
abstract interface class LectorNotasDelLugar {
  /// La nota más reciente de [ubicacionId] que no esté dada de baja, o `null` si no tiene ninguna.
  /// Se actualiza sola cuando se agrega o se borra una. Un error de lectura sale por el `Stream`.
  Stream<NotaDelLugar?> observarMasReciente(String ubicacionId);
}

import '../entities/persona_para_vender.dart';

/// Las personas a las que la colportora puede venderles desde la pestaña Ventas (HU-VEN-001, «+
/// Registrar venta»), leídas del teléfono: las personas activas de espacios activos, una fila por
/// vínculo con un espacio.
abstract interface class LectorDePersonasParaVender {
  /// Las personas de [colportorId], sin orden (quien las muestra las ordena), que se actualiza sola
  /// cuando se agrega o se da de baja una. Un error de lectura sale por el `Stream`.
  Stream<List<PersonaParaVender>> observar(String colportorId);
}

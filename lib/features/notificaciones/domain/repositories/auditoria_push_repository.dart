/// La auditoría del teléfono para las push remotas (`audit_log_local`, solo local, nunca sale del
/// dispositivo).
abstract interface class AuditoriaPushRepository {
  /// Deja constancia de una push descartada por traer datos que no son un tipo ni un UUID
  /// (`push_pii_detected`, HU-NOT-003). [campos] son los nombres de los campos, **nunca** sus valores.
  /// Lanza si no puede escribir.
  Future<void> registrarDatosPersonales({required List<String> campos, required DateTime ahora});
}

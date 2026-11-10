import 'package:colportores_mobile/features/notificaciones/domain/repositories/auditoria_push_repository.dart';

/// [AuditoriaPushRepository] en memoria: anota lo que se auditó, para los tests de la app entera
/// (donde no hay base real).
final class AuditoriaPushEnMemoria implements AuditoriaPushRepository {
  /// Los campos de cada push descartada, en orden.
  final descartadas = <List<String>>[];

  @override
  Future<void> registrarDatosPersonales({
    required List<String> campos,
    required DateTime ahora,
  }) async => descartadas.add(campos);
}

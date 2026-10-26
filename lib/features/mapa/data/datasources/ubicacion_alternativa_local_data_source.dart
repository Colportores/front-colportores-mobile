import '../../domain/entities/espacio_persona.dart';
import '../../domain/entities/estado_ubicacion_alternativa.dart';
import '../../domain/entities/motivo_rechazo_ubicacion_alternativa.dart';
import '../../domain/entities/ubicacion.dart';

/// Persistencia local de la ubicación alternativa de cobranza (HU-UBI-013), sobre la columna
/// `ubicacion_cobranza_alt_id` de `espacio_persona`. La implementa
/// `UbicacionAlternativaLocalDataSourceDrift`.
///
/// El vínculo sube al sync solo con ids (ADR-017): cada cambio se encola dentro de la misma transacción
/// que lo escribe (contrato-sync-engine §3). La persona no se toca.
abstract interface class UbicacionAlternativaLocalDataSource {
  Stream<EstadoUbicacionAlternativa> observar({
    required String personaId,
    required String espacioId,
  });

  Stream<List<Ubicacion>> observarCandidatas({
    required String colportorId,
    required String espacioId,
  });

  /// Escribe la alternativa y encola el `update` del vínculo en **una** transacción; si el encolado
  /// falla, no queda nada. Si ya era esa, no escribe ni encola y devuelve el vínculo.
  ///
  /// Lanza [UbicacionAlternativaRechazadaException] si el vínculo no está activo, la persona, el
  /// espacio o su ubicación están de baja, o la elegida no existe, no es de [colportorId], está de
  /// baja o es la del propio espacio.
  Future<EspacioPersona> establecer({
    required String personaId,
    required String espacioId,
    required String ubicacionId,
    required String colportorId,
    required DateTime ahora,
  });

  /// Pone la alternativa en `NULL` y encola el `update`. Si no había, no escribe ni encola. Mismas
  /// condiciones sobre el vínculo, la persona y el espacio que [establecer]; la alternativa vieja
  /// puede estar de baja.
  Future<EspacioPersona> quitar({
    required String personaId,
    required String espacioId,
    required DateTime ahora,
  });
}

/// La persistencia rechazó la operación por [motivo]; el repositorio la traduce a un `Failure`.
final class UbicacionAlternativaRechazadaException implements Exception {
  const UbicacionAlternativaRechazadaException(this.motivo);

  final MotivoRechazoUbicacionAlternativa motivo;

  @override
  String toString() => 'UbicacionAlternativaRechazadaException(${motivo.name})';
}

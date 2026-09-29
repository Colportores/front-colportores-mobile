import '../../domain/services/criterio_duplicado_ubicacion.dart';
import '../models/espacio_model.dart';
import '../models/ubicacion_model.dart';

/// Resultado de [UbicacionLocalDataSource.insertar]: la ubicación guardada y si ya estaba.
typedef InsercionUbicacion = ({UbicacionModel ubicacion, bool yaEstaba});

/// Persistencia local de las ubicaciones y sus espacios.
///
/// La implementación real es `UbicacionLocalDataSourceDrift`, sobre las tablas `ubicacion` y
/// `espacio` de la DB cifrada.
abstract interface class UbicacionLocalDataSource {
  /// Inserta [ubicacion] y, si viene, [espacio], y encola el sync de las dos, **todo en una
  /// transacción** (HU-UBI-001; contrato-sync-engine §3):
  ///
  /// - Si ya hay una ubicación con ese `id`, no escribe nada y la devuelve con `yaEstaba: true`
  ///   (alta idempotente).
  /// - Si llega [duplicados] y hay candidatas, no escribe nada y lanza
  ///   [UbicacionDuplicadaException].
  /// - Si el encolado falla, la transacción se revierte y la excepción sale tal cual.
  Future<InsercionUbicacion> insertar(
    UbicacionModel ubicacion, {
    EspacioModel? espacio,
    CriterioDuplicadoUbicacion? duplicados,
  });
}

/// El alta encontró candidatas a duplicado; el repositorio la traduce a `AltaConDuplicados`.
final class UbicacionDuplicadaException implements Exception {
  const UbicacionDuplicadaException(this.candidatas);

  /// De la más cercana a la más lejana.
  final List<UbicacionModel> candidatas;

  /// Solo la cantidad: las candidatas llevan dirección y no van a un log.
  @override
  String toString() => 'UbicacionDuplicadaException(${candidatas.length})';
}

import '../../domain/entities/marcador_mapa.dart';
import '../../domain/services/criterio_duplicado_ubicacion.dart';
import '../../domain/value_objects/area_mapa.dart';
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

  /// La ubicación [id] (con baja o sin ella) o `null` si no está.
  Future<UbicacionModel?> obtener(String id);

  /// Cuántos espacios sin baja tiene [ubicacionId].
  Future<int> contarEspaciosActivos(String ubicacionId);

  /// Escribe [nueva] sobre la fila con su mismo `id` y encola el `update` con la fila entera,
  /// **todo en una transacción** (HU-UBI-004; contrato-sync-engine §3). Solo cambian `tipo`,
  /// `calle`, `numero`, `lat`, `lon`, `ciudad_id`, `updated_at` y `deleted_at`: el resto de la fila
  /// (incluida `sync_version`) queda como está.
  ///
  /// - Sin fila con ese `id`: lanza [UbicacionInexistenteException].
  /// - Si `updated_at` de la fila no es [baseUpdatedAt] (cambió desde que se leyó): no escribe y
  ///   lanza [UbicacionCambioException].
  /// - Si llega [duplicados] y hay candidatas (que nunca incluyen a la misma ubicación): no
  ///   escribe y lanza [UbicacionDuplicadaException].
  /// - Si el encolado falla, la transacción se revierte y la excepción sale tal cual.
  Future<UbicacionModel> actualizar(
    UbicacionModel nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
  });

  /// Pone o saca la baja de la ubicación [id] (`deleted_at` = [deletedAt], `null` reactiva), con
  /// `updated_at` = [updatedAt], y encola —**todo en una transacción**, HU-UBI-005— el `delete`
  /// (tombstone) si [deletedAt] no es `null` o el `update` si reactiva, con la fila entera. No
  /// toca los espacios ni el resto de la fila (incluida `sync_version`).
  ///
  /// - Sin fila con ese `id`: [UbicacionInexistenteException].
  /// - Si la fila ya está de baja (o activa, al reactivar), la devuelve sin escribir ni encolar,
  ///   con cualquier [baseUpdatedAt]: es el segundo de dos toques que se pisaron.
  /// - Si no, y `updated_at` de la fila no es [baseUpdatedAt]: [UbicacionCambioException].
  /// - Si el encolado falla, la transacción se revierte.
  Future<UbicacionModel> cambiarBaja(
    String id, {
    required DateTime baseUpdatedAt,
    required DateTime updatedAt,
    required DateTime? deletedAt,
  });

  /// Ubicaciones cuyo `created_by` es [colportorId] (filtro opcional por [ciudadId]), con las bajas
  /// solo si [incluirBajas]. Emite de nuevo ante cualquier cambio de la tabla (stream Drift, §8.8).
  Stream<List<UbicacionModel>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  });

  /// Marcadores de las ubicaciones activas del colportor dentro de [area], con la cantidad de
  /// espacios sin baja. Es una proyección de lectura (no un modelo de sync): devuelve la entidad.
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
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

/// La ubicación que se quiso actualizar no existe.
final class UbicacionInexistenteException implements Exception {
  const UbicacionInexistenteException();

  @override
  String toString() => 'UbicacionInexistenteException';
}

/// La fila cambió entre que se leyó y que se quiso guardar.
final class UbicacionCambioException implements Exception {
  const UbicacionCambioException();

  @override
  String toString() => 'UbicacionCambioException';
}

import '../../domain/entities/color_house_status.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/espacios_activos.dart';
import '../../domain/entities/marcador_mapa.dart';
import '../../domain/services/criterio_duplicado_ubicacion.dart';
import '../../domain/value_objects/area_mapa.dart';
import '../models/espacio_model.dart';
import '../models/ubicacion_model.dart';

/// Resultado de [UbicacionLocalDataSource.insertar]: la ubicación guardada y si ya estaba.
typedef InsercionUbicacion = ({UbicacionModel ubicacion, bool yaEstaba});

/// Lo que hizo [UbicacionLocalDataSource.unirDuplicada].
typedef UnionLocal = ({
  bool escribio,
  int espaciosPasados,
  int espaciosFundidos,
  bool conservadaPasoAEdificio,
});

/// Una ubicación con la cantidad de espacios sin baja que tiene, el color de su fila de
/// `house_status` (`null` si no tiene: la casa es «Sin visita») y, si está de baja, el motivo con que
/// se dio de baja (`audit_log` local) y la hora de su próxima entrevista agendada (`null` si no tiene),
/// para la lista y el mapa (HU-UBI-002, HU-UBI-003, HU-UBI-005, HU-VIS-005, #491).
typedef UbicacionConEspacios = ({
  UbicacionModel ubicacion,
  int cantidadEspacios,
  ColorHouseStatus? color,
  String? motivoBaja,
  DateTime? proximaEntrevista,
});

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
  /// - Si llega [justificacion] (el texto de «Crear igual»), se guarda en el `audit_log` local
  ///   (`ubicacion_crear_igual`) con el `id` de la ubicación, **en la misma transacción** y solo si
  ///   la inserta (no si ya estaba ni si frena por duplicados). No va a la cola de sync.
  Future<InsercionUbicacion> insertar(
    UbicacionModel ubicacion, {
    EspacioModel? espacio,
    CriterioDuplicadoUbicacion? duplicados,
    String? justificacion,
  });

  /// La ubicación [id] (con baja o sin ella) o `null` si no está.
  Future<UbicacionModel?> obtener(String id);

  /// Cuántos espacios sin baja tiene [ubicacionId].
  Future<int> contarEspaciosActivos(String ubicacionId);

  /// Los espacios sin baja de [ubicacionId]: cuántos son y, si es uno solo, su `numero_depto` (`null`
  /// si no tiene). Emite la cuenta de ahora al suscribirse y de nuevo cada vez que cambia —un
  /// espacio que llega del sync, que se da de baja o al que se le cambia el número—, sin repetir un
  /// valor igual al anterior. Una sola consulta agregada: no trae las filas.
  Stream<EspaciosActivos> observarEspaciosActivos(String ubicacionId);

  /// Escribe [nueva] sobre la fila con su mismo `id` y encola el `update` con la fila entera,
  /// **todo en una transacción** (HU-UBI-004; contrato-sync-engine §3). Solo cambian `tipo`,
  /// `calle`, `numero`, `lat`, `lon`, `ciudad_id`, `zona_id` (la que calculó el caso de uso por la
  /// posición, #231), `updated_at` y `deleted_at`: el resto de la fila (incluida `sync_version`)
  /// queda como está.
  ///
  /// - Sin fila con ese `id`: lanza [UbicacionInexistenteException].
  /// - Si `updated_at` de la fila no es [baseUpdatedAt] (cambió desde que se leyó): no escribe y
  ///   lanza [UbicacionCambioException].
  /// - Si [reduceAUnEspacio] (el cambio de tipo la deja con un solo espacio: de `EDIFICIO` a
  ///   `CASA` o `NEGOCIO`, o de `NEGOCIO` a `CASA`, S17), **dentro de la
  ///   misma transacción** se cuentan los espacios sin baja: con dos o más no escribe nada y lanza
  ///   [UbicacionConEspaciosException]; con exactamente uno, a ese espacio se le quita el
  ///   `numero_depto` (con `updated_at` = el de [nueva]; `piso` y el resto quedan
  ///   igual) y se encola su `update` con la fila entera, después del de la ubicación. Si ya no
  ///   tenía número, no se escribe ni se encola nada del espacio. Los espacios dados de baja no
  ///   cuentan ni se tocan. Con **ninguno** y con [espacioSiNoTiene] (el caso de uso lo manda al
  ///   pasar a `CASA`), se inserta ese espacio y se encola su `insert` —después del `update` de la
  ///   ubicación— en la misma transacción: una casa nunca queda sin espacio (S13).
  /// - Si la fila está de baja y [nueva] la reactiva (`deleted_at` nulo) y esa baja nació de unir
  ///   duplicados (`duplicado_de_*` en la auditoría local, con la misma marca que `deleted_at`): no
  ///   escribe y lanza [ReactivacionDeUnionException]. Va antes que la búsqueda de duplicados: una
  ///   unión no se reactiva por nada.
  /// - Si llega [duplicados] y hay candidatas (que nunca incluyen a la misma ubicación): no
  ///   escribe y lanza [UbicacionDuplicadaException].
  /// - Si el encolado falla, la transacción se revierte y la excepción sale tal cual.
  /// - Si llega [justificacion] («Crear igual» de la edición), se guarda en el `audit_log` local
  ///   (`ubicacion_crear_igual`) con el `id` de la ubicación y el `updated_at` nuevo, en la misma
  ///   transacción y solo si escribe. No va a la cola de sync.
  Future<UbicacionModel> actualizar(
    UbicacionModel nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
    bool reduceAUnEspacio = false,
    EspacioModel? espacioSiNoTiene,
    String? justificacion,
  });

  /// Pone o saca la baja de la ubicación [id] (`deleted_at` = [deletedAt], `null` reactiva), con
  /// `updated_at` = [updatedAt], y encola —**todo en una transacción**, HU-UBI-005— el `delete`
  /// (tombstone) si [deletedAt] no es `null` o el `update` si reactiva, con la fila entera. No
  /// toca los espacios ni el resto de la fila (incluida `sync_version`).
  ///
  /// Con [motivo] (no vacío, solo al dar de baja), escribe también —**en la misma transacción**— una
  /// fila `ubicacion_baja` en el `audit_log` local (R-UB09), con el `id` de la ubicación, el motivo y
  /// la misma marca que `deleted_at`: así la lista encuentra el motivo de la baja vigente. El motivo
  /// no sale de la DB.
  ///
  /// Devuelve la fila como quedó y si se escribió.
  ///
  /// - Sin fila con ese `id`: [UbicacionInexistenteException].
  /// - Si llega [conservadaId] —la ubicación que se conserva al marcar un duplicado, HU-UBI-006—,
  ///   esa otra ubicación tiene que seguir activa **dentro de la misma transacción**: si no está,
  ///   [UbicacionInexistenteException]; si está de baja, [ConservadaDeBajaException]. Así dos
  ///   "marcar duplicado" concurrentes sobre pares que se cruzan no dejan de baja a las dos.
  /// - Si la fila ya está de baja (o activa, al reactivar), la devuelve con `escribio: false`, sin
  ///   escribir ni encolar, con cualquier [baseUpdatedAt]: es el segundo de dos toques que se
  ///   pisaron.
  /// - Si no, y `updated_at` de la fila no es [baseUpdatedAt]: [UbicacionCambioException].
  /// - Al **reactivar** (`deletedAt` nulo sobre una fila de baja), **dentro de la misma transacción**
  ///   y antes de escribir (HU-UBI-005, «Reactivar»): si esa baja nació de unir duplicados
  ///   (`duplicado_de_*` en la auditoría local, con la misma marca que `deleted_at`): no escribe y
  ///   lanza [ReactivacionDeUnionException]; si llega [duplicados] y hay candidatas (con el criterio
  ///   de `alSeguirIgual` son solo las que chocan por D1: la misma dirección a menos de 100 m): no
  ///   escribe y lanza [UbicacionDuplicadaException].
  /// - Si el encolado falla, la transacción se revierte.
  Future<({UbicacionModel ubicacion, bool escribio})> cambiarBaja(
    String id, {
    required DateTime baseUpdatedAt,
    required DateTime updatedAt,
    required DateTime? deletedAt,
    String? motivo,
    String? conservadaId,
    CriterioDuplicadoUbicacion? duplicados,
  });

  /// La unión de un par de duplicados en una sola transacción (HU-UBI-006). Ver
  /// `UbicacionRepository.unirDuplicada`.
  ///
  /// Lanza [UbicacionInexistenteException] si falta una de las dos y [ConservadaDeBajaException] si
  /// la conservada está de baja. Lo que lance el encolado (no hay motor de sync, #178) revierte la
  /// transacción entera.
  Future<UnionLocal> unirDuplicada(
    String conservadaId,
    String duplicadaId, {
    required DateTime ahora,
  });

  /// Ubicaciones cuyo `created_by` es [colportorId] (filtro opcional por [ciudadId]), con las bajas
  /// solo si [incluirBajas]. Emite de nuevo ante cualquier cambio de la tabla (stream Drift, §8.8).
  Stream<List<UbicacionModel>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  });

  /// Lo mismo que [observarDelColportor] (sin filtro de ciudad), cada ubicación con la cantidad de
  /// espacios sin baja que tiene, el color de su `house_status` vigente y el motivo de su baja vigente:
  /// un solo `JOIN` con `COUNT` (HU-UBI-002, HU-UBI-005, HU-VIS-005). Emite de nuevo cuando cambia
  /// `house_status`: el mapa y la lista se repintan solos al guardar una visita.
  Stream<List<UbicacionConEspacios>> observarListaDelColportor({
    required String colportorId,
    bool incluirBajas = false,
  });

  /// Marcadores de las ubicaciones activas del colportor dentro de [area], con la cantidad de
  /// espacios sin baja. Es una proyección de lectura (no un modelo de sync): devuelve la entidad.
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  });
}

/// El alta o la edición encontró candidatas a duplicado; el repositorio la traduce a
/// `AltaConDuplicados` o `ModificacionConDuplicados`. Al reactivar una baja, a
/// `FailureReactivacionChocaConActiva` (D1).
final class UbicacionDuplicadaException implements Exception {
  const UbicacionDuplicadaException(this.candidatas);

  /// De la más cercana a la más lejana, con entidades de dominio.
  final List<CandidataDuplicado> candidatas;

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

/// Se quiso reducir una ubicación a un solo espacio (de `EDIFICIO` a `CASA` o `NEGOCIO`, o de
/// `NEGOCIO` a `CASA`) teniendo [cantidad] espacios activos (dos o más, S17); el repositorio la
/// traduce a `FailureUbicacionConEspacios`.
final class UbicacionConEspaciosException implements Exception {
  const UbicacionConEspaciosException(this.cantidad);

  final int cantidad;

  @override
  String toString() => 'UbicacionConEspaciosException($cantidad)';
}

/// Se quiso reactivar una baja que nació de unir duplicados (HU-UBI-005, «Reactivar»); el repositorio
/// la traduce a `FailureReactivacionDeUnion`.
final class ReactivacionDeUnionException implements Exception {
  const ReactivacionDeUnionException({this.conservadaId});

  /// La ubicación a la que se unió (la `A` de `duplicado_de_A`), si el motivo la trae; si `A` también
  /// se unió a otra (B -> A -> C), la que sigue la cadena (C). Puede estar de baja o no existir:
  /// quien la traduce mira si sigue activa.
  final String? conservadaId;

  /// Sin el uuid: la excepción puede terminar en un log.
  @override
  String toString() => 'ReactivacionDeUnionException';
}

/// Al marcar un duplicado, la ubicación que se conserva ya está de baja (HU-UBI-006).
final class ConservadaDeBajaException implements Exception {
  const ConservadaDeBajaException();

  @override
  String toString() => 'ConservadaDeBajaException';
}

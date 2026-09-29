import '../../domain/entities/motivo_rechazo_espacio.dart';
import '../models/espacio_model.dart';
import '../models/ubicacion_model.dart';

/// Resultado de [EspacioLocalDataSource.insertarEspacio]: el espacio guardado y si ya estaba.
typedef InsercionEspacio = ({EspacioModel espacio, bool yaEstaba});

/// Persistencia local de la gestión de espacios (HU-UBI-007), sobre las tablas `espacio` y
/// `ubicacion` de la DB cifrada. La implementa `UbicacionLocalDataSourceDrift`.
///
/// Cada escritura corre **en una transacción** con el encolado del sync de la fila
/// (contrato-sync-engine §3): si el encolado falla, la escritura se revierte. Las reglas que
/// dependen del estado de la DB salen como [EspacioRechazadoException].
abstract interface class EspacioLocalDataSource {
  /// Inserta [espacio] y encola su `insert`. La ubicación ya se encoló cuando se creó, así que en
  /// la cola la ubicación siempre va antes que sus espacios.
  ///
  /// - Si ya hay un espacio con ese `id`, no escribe nada y lo devuelve con `yaEstaba: true`.
  /// - La ubicación tiene que existir, estar activa y no ser `CASA`; el `numero_depto` no puede
  ///   repetir el de otro espacio activo de la misma ubicación (sin distinguir mayúsculas).
  Future<InsercionEspacio> insertarEspacio(EspacioModel espacio);

  /// Cambia el `numero_depto` de [id] y encola el `update` con la fila entera. No toca
  /// `sync_version` (la asigna el servidor). Si el valor no cambia, no escribe ni encola.
  ///
  /// El espacio tiene que existir y estar activo, su ubicación no puede ser `CASA` (el espacio
  /// default no se edita) y el número no puede repetir el de otro espacio activo.
  Future<EspacioModel> actualizarNumeroDepto(
    String id, {
    required String numeroDepto,
    required DateTime ahora,
  });

  /// Baja lógica: marca `deleted_at` y encola el `update`. Si ya estaba de baja no hace nada. La
  /// ubicación no puede ser `CASA`.
  Future<EspacioModel> darDeBajaEspacio(String id, {required DateTime ahora});

  /// Deshace la baja. Si ya estaba activo no hace nada. La ubicación tiene que estar activa y el
  /// número no puede repetir el de otro espacio activo.
  Future<EspacioModel> restaurarEspacio(String id, {required DateTime ahora});

  /// El espacio [id] y su ubicación, o `null` si el espacio no existe.
  Future<({EspacioModel espacio, UbicacionModel ubicacion})?> buscarEspacio(String id);

  /// Espacios de [ubicacionId] ordenados por `numero_depto`; solo los activos salvo [incluirBajas].
  Future<List<EspacioModel>> listarEspacios(String ubicacionId, {bool incluirBajas = false});

  /// Cantidad de espacios activos de [ubicacionId].
  Future<int> contarEspaciosActivos(String ubicacionId);
}

/// La persistencia rechazó la operación por [motivo]; el repositorio la traduce a un `Failure`.
final class EspacioRechazadoException implements Exception {
  const EspacioRechazadoException(this.motivo);

  final MotivoRechazoEspacio motivo;

  @override
  String toString() => 'EspacioRechazadoException(${motivo.name})';
}

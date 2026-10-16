// R-A2: todo acceso del núcleo al mundo exterior pasa por un puerto declarado
// acá —interfaz Dart pura, sin plugins— con un fake en lib/src/testing/.
//
// El núcleo declara QUÉ necesita; quién se lo da es problema de
// lib/src/adapters/, que es el único lugar del paquete que conoce un plugin.

import 'backup.dart';
import 'model.dart';
import 'queue.dart';

/// El camino batch hacia el backend (§6: a través de `bff-colportores`).
///
/// Lo implementan `BffTransport` en producción y [FakeSyncTransport] en los
/// tests y en el desarrollo de la app entre hitos (§11).
///
/// Toda implementación falla lanzando [TransportFailure] y nunca deja escapar
/// una excepción de su propia tecnología (`DioException`, `SocketException`):
/// el núcleo no sabría clasificarla, y clasificar es justo lo que decide entre
/// `PENDING` e `INVALID`.
abstract interface class SyncTransport {
  /// Sube un lote (§5.5). Devuelve un resultado por job; un job inválido no
  /// tumba a los demás. Lanza [TransportFailure] si falló la llamada entera.
  Future<PushResult> push(PushBatch batch);

  /// Baja el delta de [entities] desde [watermark].
  ///
  /// [watermark] nulo es una réplica desde cero: la primera sync, la fase 4 de
  /// §7 (catálogos) o una entidad recién registrada.
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  });
}

/// Conectividad, uno de los tres triggers de §5.2.
///
/// Lo implementa `ConnectivityPlusAdapter` sobre `connectivity_plus`.
abstract interface class ConnectivityPort {
  Stream<bool> get onlineChanges;
  Future<bool> get isOnline;
}

/// `sync_queue` en la DB local (Drift).
///
/// El núcleo no importa Drift: define acá lo que necesita de la cola y el
/// adaptador de la app lo implementa. Que [append] sea llamable dentro de la
/// misma transacción en la que la app escribe la fila de negocio es parte del
/// contrato (§3): o entran las dos cosas, o no entra ninguna.
abstract interface class JobStorePort {
  /// Encola un job en `PENDING`. Devuelve su id local.
  Future<String> append(SyncJob job);

  /// Toma hasta [limit] jobs `PENDING` **en orden de creación** y los pasa a
  /// `IN_FLIGHT` (§5.5).
  Future<List<QueuedJob>> claimPending({int limit});

  /// `IN_FLIGHT` → `DONE`.
  Future<void> markDone(Iterable<String> jobIds, {required DateTime at});

  /// `IN_FLIGHT` → `INVALID`. Queda visible y no se reintenta solo (§5.1).
  Future<void> markInvalid(String jobId,
      {required String code, String message});

  /// `IN_FLIGHT` → `PENDING`. Es la vuelta atrás de un error transitorio: el
  /// ciclo se corta y estos jobs se reintentan al próximo trigger.
  Future<void> markPending(Iterable<String> jobIds);

  /// `INVALID` → `PENDING`, tras corregir el dato (§3, `engine.requeue`).
  Future<void> requeue(String jobId);

  /// Borra jobs de `INVALID`. Devuelve cuántos borró.
  ///
  /// Es la contracara de [requeue], y hace falta porque no todo error es
  /// corregible. Un payload que viola una constraint del servidor —un
  /// `pk_producto` nulo, una fecha que no es fecha— vuelve a ser rechazado por
  /// el mismo motivo cada vez que se lo reintenta. Sin una salida, ese job se
  /// queda en la cola de error para siempre y el contador deja de significar
  /// "hay algo que atender": el colportor aprende a ignorarlo, y el día que
  /// aparece un error de verdad tampoco lo mira.
  ///
  /// Solo toca lo que está en `INVALID`. Pasarle el id de un `PENDING` no
  /// borra nada —esa venta todavía va a subir— y el de un `IN_FLIGHT` tampoco:
  /// hay un ciclo que lo tiene en la mano, y sacárselo por abajo lo dejaría
  /// resolviendo un job que ya no existe.
  Future<int> discardInvalid(Iterable<String> jobIds);

  /// Los `IN_FLIGHT` que llevan más de [staleAfter] sin resolverse → `PENDING`.
  /// Devuelve cuántos.
  ///
  /// Un job queda `IN_FLIGHT` mientras un ciclo lo tiene en la mano. Si el
  /// proceso muere ahí —Android matando la app, batería, un bug del
  /// adaptador—, nadie lo reclama: `claimPending` no lo mira y la venta no sube
  /// nunca.
  ///
  /// **Por qué hay una antigüedad y no se reclama todo.** El trabajo en segundo
  /// plano (RF-SY07) corre en **otro isolate**, con su propio motor y su propia
  /// conexión a la misma base. Un reclamo incondicional ahí se llevaría puestos
  /// los jobs que el primer plano está mandando **en ese momento**, y los
  /// mandaría de nuevo en paralelo. No se duplica ninguna venta —el
  /// `client_op_id` hace que el servidor conteste `duplicate` (§5.3)— pero el
  /// colportor paga el viaje dos veces, que es justo lo que RR-07 cuida.
  ///
  /// El motor lo llama en **cada** ciclo, no una vez por arranque: así un job
  /// que quedó colgado se recupera solo, sin esperar a que alguien reinicie la
  /// app.
  Future<int> reclaimInFlight(Duration staleAfter);

  Future<SyncStatus> status();

  /// Los jobs en `INVALID`, del más reciente al más viejo.
  ///
  /// Es lo que la app necesita para mostrar la cola de error (RF-SY06): sin
  /// esto, `status()` dice "3 en error" y no hay manera de saber cuáles, ni de
  /// llamar a `requeue(jobId)` con nada.
  Future<List<QueuedJob>> listInvalid({int limit});

  /// Compacta los `DONE` anteriores a [before] (§5.8: 7 días).
  Future<int> purgeDone(DateTime before);
}

/// La DB local, del lado de las tablas de negocio.
abstract interface class LocalStorePort {
  /// Aplica el delta y guarda el watermark **en una sola transacción** (§10).
  ///
  /// Es indivisible a propósito: si aplicar falla, el watermark no avanza y el
  /// próximo pull vuelve a traer lo mismo. Dos métodos separados dejarían la
  /// puerta abierta a avanzar el watermark sobre datos que no se escribieron.
  Future<void> applyDelta(
    Map<String, List<Map<String, Object?>>> rows, {
    required String scope,
    required String watermark,
  });

  /// El watermark guardado para [scope], o `null` si nunca se pulleó.
  Future<String?> watermarkOf(String scope);
}

/// El `appDataFolder` de Google Drive (ADR-003). Va directo, sin BFF (§6).
///
/// Lo implementa `DriveAdapter` sobre `googleapis` + `google_sign_in`.
abstract interface class ArchivePort {
  /// OAuth (HU-SYNC-004). `false` si el usuario no autorizó.
  Future<bool> authorize();
  Future<bool> get isAuthorized;

  /// Metadatos de la cadena, sin bajar los payloads.
  Future<List<BackupEntry>> list();

  /// Sube un payload **ya cifrado** y devuelve la entrada creada.
  Future<BackupEntry> upload({
    required List<int> payload,
    required String? parentId,
    required String watermark,
  });

  Future<List<int>> download(String id);
}

/// Cifrado E2E con la clave del usuario (ADR-003).
///
/// El núcleo no elige algoritmo ni maneja la clave: eso es del adaptador, que
/// delega en el crypto nativo del OS vía `cryptography_flutter`. Acá solo se
/// sabe que lo que sale de [encrypt] es lo único que puede tocar la red.
abstract interface class CryptoPort {
  Future<List<int>> encrypt(List<int> plaintext);
  Future<List<int>> decrypt(List<int> ciphertext);

  /// Hash del payload cifrado, para la integridad de la cadena.
  String digest(List<int> bytes);
}

/// La DB local vista como archivo: exportar para el backup, reemplazar para el
/// restore.
abstract interface class SnapshotPort {
  /// Exporta el estado local. `null` en [since] es un backup completo; con
  /// fecha, el incremental desde ese punto.
  ///
  /// **Incluye `sync_queue`** (§7 fase 1): los jobs encolados al momento del
  /// backup tienen que volver a existir, o se pierden las ventas que estaban
  /// esperando subir.
  Future<List<int>> export({DateTime? since});

  /// Reconstruye la DB aplicando los payloads en orden, de la base a la punta.
  ///
  /// Se arma en un archivo temporal y recién al final reemplaza la DB en uso
  /// (ADR-003, HU-SYNC-006): un restore que falla a la mitad no puede dejar al
  /// colportor sin la DB que tenía.
  Future<void> restore(List<List<int>> payloadsInOrder);
}

/// Supabase Realtime (§5.6). Va directo, sin BFF (§6).
///
/// Emite **el nombre de la entidad que cambió, y nada más**. El payload del
/// evento se ignora a propósito: aplicarlo sería un segundo camino por el que
/// entran datos a la DB local, con su propio orden y sus propios huecos si un
/// evento se pierde. El evento es un timbre; lo que entra es siempre el mismo
/// delta por REST que usa el ciclo batch.
abstract interface class RealtimePort {
  /// Se suscribe a [entities]. Volver a llamarla reemplaza la suscripción
  /// anterior — es lo que hace la fase 4 de §7 en el dispositivo nuevo.
  Stream<String> subscribe(List<String> entities);

  Future<void> unsubscribe();
}

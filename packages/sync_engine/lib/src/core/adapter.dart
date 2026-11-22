// La única pieza por-entidad que escribe la app (§3).
//
// Todo lo demás del motor es genérico. Acá es donde una tabla Drift se
// convierte en algo que el backend entiende y viceversa.

/// Traduce entre una fila de la DB local y su forma remota.
///
/// La app escribe uno por cada entidad `push` o `pull`. Las `local` no llevan:
/// no tienen forma remota porque nunca salen del dispositivo.
abstract class SyncTableAdapter<T> {
  const SyncTableAdapter();

  /// Nombre de la entidad en el backend. Es la clave que usa todo el motor:
  /// el `SyncSpec`, el job en la cola y el delta del pull.
  String get remoteName;

  /// Lo que viaja hacia el backend.
  ///
  /// **Acá es donde no puede aparecer un dato personal** de una entidad que no
  /// sea `local`. Es el punto exacto que vigila la lista negra de §9 del
  /// contrato de datos.
  Map<String, Object?> toSyncJson(T row);

  /// Lo que baja del backend, de vuelta a una fila local.
  T fromSyncJson(Map<String, Object?> json);

  /// La PK que viaja en el payload: un UUID v7 generado en el dispositivo.
  /// De esto depende que el replay de §7 sea idempotente.
  Object pkOf(T row);

  /// La versión de la fila, para el LWW de §5.4.
  int syncVersionOf(T row);
}

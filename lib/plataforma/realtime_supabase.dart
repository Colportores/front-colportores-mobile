import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sync_engine/sync_engine.dart';

/// [RealtimePort] sobre Supabase Realtime (contrato-sync-engine §5.6): un canal con un
/// `postgres_changes` por cada tabla `realtime` del catálogo.
///
/// **El evento es un timbre y nada más.** Emite el nombre de la tabla que cambió y descarta el
/// payload: lo que entra a la DB local es siempre el delta por `sync_pull`, el mismo camino que el
/// ciclo batch, con su watermark y sus huecos cubiertos. Un evento perdido no deja nada a medias:
/// el próximo pull trae lo que faltó. Realtime pasa por la RLS con el JWT de la sesión, así que
/// solo suena por lo que el colportor puede ver.
final class RealtimeSupabase implements RealtimePort {
  RealtimeSupabase(this._cliente);

  final SupabaseClient _cliente;
  RealtimeChannel? _canal;
  StreamController<String>? _salida;

  @override
  Stream<String> subscribe(List<String> entities) {
    // Volver a suscribirse reemplaza la suscripción anterior (§7, fase 4).
    unawaited(_soltar(_canal, _salida));
    final salida = StreamController<String>.broadcast();
    var canal = _cliente.channel('sync-catalogo');
    for (final entidad in entities) {
      canal = canal.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: entidad,
        callback: (_) {
          if (!salida.isClosed) salida.add(entidad);
        },
      );
    }
    _canal = canal..subscribe();
    _salida = salida;
    return salida.stream;
  }

  @override
  Future<void> unsubscribe() {
    final canal = _canal;
    final salida = _salida;
    _canal = null;
    _salida = null;
    return _soltar(canal, salida);
  }

  Future<void> _soltar(RealtimeChannel? canal, StreamController<String>? salida) async {
    if (canal != null) await _cliente.removeChannel(canal);
    await salida?.close();
  }
}

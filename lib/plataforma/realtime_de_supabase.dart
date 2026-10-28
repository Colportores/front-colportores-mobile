import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sync_engine/sync_engine.dart';

import '../core/logging/app_logger.dart';

/// Escucha los INSERT y UPDATE de tablas de Postgres. Es la costura de [RealtimeDeSupabase] con
/// `supabase_flutter`: así su lógica (qué se avisa, qué pasa al volver a suscribirse o al
/// reconectar) se prueba sin un servidor de Realtime.
abstract interface class FuenteDeCambios {
  /// Empieza a escuchar [tablas] (esquema `public`). Devuelve cómo dejar de escuchar.
  ///
  /// - [alCambiar]: llegó un INSERT o un UPDATE de esa tabla (un soft delete es un UPDATE).
  /// - [alReconectar]: el canal volvió después de haberse caído; lo que pasó mientras tanto no
  ///   llegó, y hay que ir a buscarlo.
  /// - [alFallar]: el canal no se pudo abrir o se cayó. La fuente reintenta sola.
  Future<void> Function() escuchar(
    List<String> tablas, {
    required void Function(String tabla) alCambiar,
    required void Function() alReconectar,
    required void Function(Object error) alFallar,
  });
}

/// [RealtimePort] del motor sobre Supabase Realtime (contrato-sync-engine §5.6, HU-SYNC-003).
///
/// **Emite el nombre de la tabla que cambió y nada más**: el contenido del evento se descarta a
/// propósito. Lo que entra a la DB local es siempre el delta del pull (el motor lo baja al recibir
/// el timbre), así que Realtime no es un segundo camino de datos con su propio orden y sus propios
/// huecos. Un evento perdido tampoco pierde datos: el próximo pull lo recupera.
///
/// Al reconectarse después de una caída (volvió la red, se renovó el token) emite un timbre más:
/// los eventos de la caída no se repiten, y sin ese timbre el cambio esperaría al próximo ciclo.
final class RealtimeDeSupabase implements RealtimePort {
  RealtimeDeSupabase(this._fuente);

  final FuenteDeCambios _fuente;

  StreamController<String>? _timbres;
  Future<void> Function()? _dejarDeEscuchar;

  @override
  Stream<String> subscribe(List<String> entities) {
    // Volver a llamarla reemplaza la suscripción anterior (el puerto lo exige).
    _cerrarLaAnterior();
    final timbres = StreamController<String>();
    _timbres = timbres;
    if (entities.isEmpty) return timbres.stream;

    // Un evento tardío de una suscripción ya reemplazada o cerrada no avisa a nadie.
    bool vigente() => identical(_timbres, timbres) && !timbres.isClosed;
    _dejarDeEscuchar = _fuente.escuchar(
      entities,
      alCambiar: (tabla) {
        if (vigente()) timbres.add(tabla);
      },
      alReconectar: () {
        if (vigente()) timbres.add(entities.first);
      },
      alFallar: (error) => AppLogger.instance.warn(
        LogModulo.sync,
        'REALTIME_CAIDO',
        'Realtime no está disponible; el próximo pull trae los cambios',
        {'tablas': entities.join(','), 'error': error.runtimeType.toString()},
      ),
    );
    return timbres.stream;
  }

  @override
  Future<void> unsubscribe() async => _cerrarLaAnterior();

  void _cerrarLaAnterior() {
    final dejar = _dejarDeEscuchar;
    final timbres = _timbres;
    _dejarDeEscuchar = null;
    _timbres = null;
    unawaited(timbres?.close());
    if (dejar == null) return;
    unawaited(
      dejar().catchError((Object e, StackTrace st) {
        // Cerrar un canal que ya estaba caído no es un problema de nadie.
        AppLogger.instance.warn(LogModulo.sync, 'REALTIME_CIERRE', 'no se pudo cerrar el canal', {
          'error': e.runtimeType.toString(),
        });
      }),
    );
  }
}

/// [FuenteDeCambios] sobre el cliente de Supabase: un canal con un `postgres_changes` por tabla y
/// por evento (INSERT, UPDATE). El token de la sesión lo mantiene `supabase_flutter`.
final class FuenteDeCambiosSupabase implements FuenteDeCambios {
  const FuenteDeCambiosSupabase(this._cliente);

  final SupabaseClient _cliente;

  @override
  Future<void> Function() escuchar(
    List<String> tablas, {
    required void Function(String tabla) alCambiar,
    required void Function() alReconectar,
    required void Function(Object error) alFallar,
  }) {
    final canal = _cliente.channel('catalogo');
    for (final tabla in tablas) {
      for (final evento in const [PostgresChangeEvent.insert, PostgresChangeEvent.update]) {
        canal.onPostgresChanges(
          event: evento,
          schema: 'public',
          table: tabla,
          callback: (_) => alCambiar(tabla),
        );
      }
    }
    var estuvoCaido = false;
    var cerrado = false;
    canal.subscribe((estado, error) {
      // El `closed` de cerrar el canal a propósito no es una caída.
      if (cerrado) return;
      switch (estado) {
        case RealtimeSubscribeStatus.subscribed:
          if (estuvoCaido) {
            estuvoCaido = false;
            alReconectar();
          }
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.closed:
          estuvoCaido = true;
          alFallar(error ?? estado);
      }
    });
    return () async {
      cerrado = true;
      await _cliente.removeChannel(canal);
    };
  }
}

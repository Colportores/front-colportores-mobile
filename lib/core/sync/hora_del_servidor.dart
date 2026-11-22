import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';
import '../logging/app_logger.dart';

/// La última hora que el **servidor** dijo en un push o en un pull (`server_time`), la única hora de
/// la que el teléfono no puede mentir. Se guarda en la propia base local (tabla `sync_meta`, clave
/// [HoraDelServidorEnDb.clave]): vive y muere con las notas, los datos y la cola que la acompañan.
///
/// La usa lo que borra para siempre por tiempo (las notas borradas hace más de 90 días, HU-UBI-012):
/// con la hora del equipo sola, adelantar la fecha del teléfono las borraría antes de tiempo.
abstract interface class HoraDelServidor {
  /// La más alta que se vio, o `null` si el teléfono nunca habló con el servidor.
  Future<DateTime?> ultima();

  /// La anota si es más alta que la guardada: una más vieja (un push repetido, un pull atrasado) no
  /// la pisa.
  Future<void> registrar(DateTime serverTime);
}

/// [HoraDelServidor] sobre `sync_meta`. Sin DB abierta (sesión cerrada) no hay dónde guardar ni qué
/// leer: `null` y nada.
final class HoraDelServidorEnDb implements HoraDelServidor {
  HoraDelServidorEnDb(this._db, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppDatabase? Function() _db;
  final AppLogger _log;

  static const clave = 'server_time_last';

  @override
  Future<DateTime?> ultima() async {
    final db = _db();
    if (db == null) return null;
    return _leer(db);
  }

  @override
  Future<void> registrar(DateTime serverTime) async {
    final db = _db();
    if (db == null) return;
    try {
      await db.transaction(() async {
        final guardada = await _leer(db);
        final nueva = serverTime.toUtc();
        if (guardada != null && !nueva.isAfter(guardada)) return;
        await db
            .into(db.syncMetas)
            .insertOnConflictUpdate(
              SyncMetasCompanion.insert(clave: clave, valor: nueva.toIso8601String()),
            );
      });
    } on Object catch (e) {
      // Anotar la hora es un favor al resto de la app: si falla, la sync sigue y solo se lee el tipo.
      _log.warn(LogModulo.sync, 'HORA_SERVIDOR_GUARDAR_FAIL', 'no se pudo anotar la hora', {
        'error': e.runtimeType.toString(),
      });
    }
  }

  /// Un valor ilegible (la fila se editó a mano) es «no hay dato», no una excepción.
  static Future<DateTime?> _leer(AppDatabase db) async {
    final fila = await (db.select(
      db.syncMetas,
    )..where((m) => m.clave.equals(clave))).getSingleOrNull();
    return fila == null ? null : DateTime.tryParse(fila.valor)?.toUtc();
  }
}

/// Con la DB abierta de la sesión (`dbLocalProvider`); se lee en cada uso, no al armarse.
final horaDelServidorProvider = Provider<HoraDelServidor>(
  (ref) => HoraDelServidorEnDb(() => ref.read(dbLocalProvider)),
);

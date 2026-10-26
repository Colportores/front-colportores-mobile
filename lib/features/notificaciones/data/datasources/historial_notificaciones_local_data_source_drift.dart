import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/instante.dart';
import '../../domain/entities/destino_notificacion.dart';
import '../../domain/entities/notificacion.dart';
import '../../domain/entities/tipo_notificacion.dart';
import '../../domain/repositories/historial_notificaciones_repository.dart';

/// El historial de avisos sobre la tabla `notificacion_historial` de la DB cifrada (HU-NOT-005).
///
/// Local-only: no encola nada para el sync. Cada escritura es una sola sentencia (una transacción
/// implícita de SQLite), así que dos llamadas seguidas —un doble toque, dos acciones antes de que
/// termine la primera— se serializan sin pisarse. Todo lo que se lee queda dentro de los últimos
/// [retencionHistorialNotificaciones] contados desde el `ahora` que pasa quien llama.
class HistorialNotificacionesLocalDataSourceDrift {
  HistorialNotificacionesLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  $NotificacionesHistorialTable get _tabla => _db.notificacionesHistorial;

  /// El corte de la retención: lo recibido antes de este instante ya no se lee.
  DateTime _corte(DateTime ahora) => instanteMs(ahora).subtract(retencionHistorialNotificaciones);

  /// `true` si la fila era nueva; `false` si ya había una con ese `id` (no se toca).
  ///
  /// Se mira y se inserta dentro de una transacción: `insertOrIgnore` no sirve para saberlo, porque
  /// Drift devuelve `last_insert_rowid()` y SQLite lo deja en el valor de la inserción anterior
  /// cuando ignora una.
  Future<bool> registrar(Notificacion notificacion) => _db.transaction(() async {
    final yaEsta =
        await (_db.select(_tabla)
              ..where((n) => n.id.equals(notificacion.id))
              ..limit(1))
            .getSingleOrNull();
    if (yaEsta != null) return false;
    await _db
        .into(_tabla)
        .insert(
          NotificacionesHistorialCompanion.insert(
            id: notificacion.id,
            tipo: notificacion.tipo.codigo,
            titulo: notificacion.titulo,
            detalle: Value(notificacion.detalle),
            destino: Value(notificacion.destino?.enlace),
            recibidaEn: notificacion.recibidaEn,
            leidaEn: Value(notificacion.leidaEn),
          ),
        );
    return true;
  });

  Stream<List<Notificacion>> observar({TipoNotificacion? tipo, required DateTime ahora}) {
    final corte = _corte(ahora);
    final consulta = _db.select(_tabla)
      ..where((n) {
        final recientes = n.recibidaEn.isBiggerOrEqualValue(corte.millisecondsSinceEpoch);
        return tipo == null ? recientes : recientes & n.tipo.equals(tipo.codigo);
      })
      ..orderBy([(n) => OrderingTerm.desc(n.recibidaEn), (n) => OrderingTerm.desc(n.id)]);
    return consulta.watch().map((filas) => [for (final f in filas) _aEntidad(f)]);
  }

  Stream<int> observarNoLeidas({required DateTime ahora}) {
    final cantidad = _tabla.id.count();
    final consulta = _db.selectOnly(_tabla)
      ..addColumns([cantidad])
      ..where(
        _tabla.leidaEn.isNull() &
            _tabla.recibidaEn.isBiggerOrEqualValue(_corte(ahora).millisecondsSinceEpoch),
      );
    return consulta.watchSingle().map((fila) => fila.read(cantidad) ?? 0).distinct();
  }

  Future<void> marcarLeida(String id, {required DateTime ahora}) async {
    await (_db.update(_tabla)..where((n) => n.id.equals(id) & n.leidaEn.isNull())).write(
      NotificacionesHistorialCompanion(leidaEn: Value(instanteMs(ahora))),
    );
  }

  Future<void> marcarTodasLeidas({required DateTime ahora}) async {
    await (_db.update(_tabla)..where((n) => n.leidaEn.isNull())).write(
      NotificacionesHistorialCompanion(leidaEn: Value(instanteMs(ahora))),
    );
  }

  Future<int> borrarTodas({DateTime? hasta}) {
    final consulta = _db.delete(_tabla);
    if (hasta != null) {
      consulta.where((n) => n.recibidaEn.isSmallerOrEqualValue(hasta.millisecondsSinceEpoch));
    }
    return consulta.go();
  }

  Future<int> purgarVencidas({required DateTime ahora}) => (_db.delete(
    _tabla,
  )..where((n) => n.recibidaEn.isSmallerThanValue(_corte(ahora).millisecondsSinceEpoch))).go();

  Notificacion _aEntidad(NotificacionFila f) => Notificacion(
    id: f.id,
    tipo: TipoNotificacion.desdeCodigo(f.tipo),
    titulo: f.titulo,
    detalle: f.detalle,
    destino: DestinoNotificacion.desdeEnlace(f.destino),
    recibidaEn: f.recibidaEn,
    leidaEn: f.leidaEn,
  );
}

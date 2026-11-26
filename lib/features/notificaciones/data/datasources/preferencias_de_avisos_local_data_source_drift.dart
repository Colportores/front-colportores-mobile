import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/sync/encolador_sync.dart';

/// Todavía no bajó la fila de preferencias de avisos de la persona (el teléfono no terminó su primera
/// sincronización): no hay una versión del servidor sobre la que guardar el cambio.
final class PreferenciasSinBajarException implements Exception {
  const PreferenciasSinBajarException();

  @override
  String toString() => 'PreferenciasSinBajarException';
}

/// Lee y escribe las preferencias de avisos de la colportora en `preferencia_de_avisos` de la DB cifrada
/// (backend-supabase 0207, #313, «Avisos s/red» de Cristian, 24/11, HU-NOT-004).
///
/// Una fila por persona, que baja con el pull y sube con el push: **cambiar un aviso no necesita conexión**. El
/// cambio queda en el teléfono al instante y su `update` queda en la cola de sync (contrato-sync-engine §3:
/// [EncoladorSync] se llama adentro de la transacción, así que la fila y su job entran juntos o ninguno).
/// El servidor mantiene la misma copia en `usuario.notif_preferences`, que es lo que lee para mandar los avisos.
///
/// - La fila es la de [_usuarioId]; si la sesión no la da (`null`), la única fila que tenga el teléfono (el pull
///   baja solo la propia).
/// - **Si la fila todavía no bajó** (el teléfono no terminó su primera sincronización) no se guarda nada: [guardar]
///   lanza [PreferenciasSinBajarException] y la pantalla dice que no pudo guardar el cambio. En el servidor la fila
///   existe siempre (se crea con la persona, backend 0207: «así un teléfono siempre actualiza una fila que bajó»),
///   y ni un `insert` (el servidor lo descarta) ni un `update` con la versión 0 (el motor aplica la fila del
///   servidor por `sync_version`, §5.4) conservan el cambio: Diego vería volver el interruptor solo, sin saberlo.
///   Es lo conservador mientras Cristian decide (pendiente P3 de #769, 26/11).
/// - Con dos cambios seguidos, cada uno encola su `update` con la versión que la fila tenía.
final class PreferenciasDeAvisosLocalDataSourceDrift {
  PreferenciasDeAvisosLocalDataSourceDrift(
    this._db, {
    required this._encolador,
    required this._usuarioId,
    DateTime Function()? ahora,
  }) : _ahora = ahora ?? DateTime.now;

  final AppDatabase _db;
  final EncoladorSync _encolador;

  /// El id de la persona con la sesión iniciada, o `null` si no se sabe.
  final String? Function() _usuarioId;
  final DateTime Function() _ahora;

  /// Lo guardado: el objeto de las preferencias, o `null` si la fila no existe todavía o no tiene nada
  /// guardado (valores de siempre).
  Future<Map<String, Object?>?> leer() async {
    final fila = await _fila();
    return fila?.notifPreferences;
  }

  /// Reemplaza lo guardado por [preferencias] entero y encola el cambio. Si la fila de la persona todavía no bajó
  /// lanza [PreferenciasSinBajarException] y no escribe nada.
  Future<void> guardar(Map<String, Object?> preferencias) => _db.transaction(() async {
    final ahora = _ahora().toUtc();
    final existente = await _fila();
    if (existente != null) {
      await (_db.update(_db.preferenciasDeAvisos)..where((f) => f.id.equals(existente.id))).write(
        PreferenciasDeAvisosCompanion(
          notifPreferences: Value(preferencias),
          updatedAt: Value(ahora),
        ),
      );
      await _encolador.encolar(
        'preferencia_de_avisos',
        OperacionSync.update,
        _payload(
          id: existente.id,
          preferencias: preferencias,
          creada: existente.createdAt,
          actualizada: ahora,
          creadaPor: existente.createdBy,
          version: existente.syncVersion,
        ),
      );
      return;
    }
    throw const PreferenciasSinBajarException();
  });

  Future<PreferenciaDeAvisosFila?> _fila() async {
    final id = _usuarioId();
    final consulta = _db.select(_db.preferenciasDeAvisos)..where((f) => f.deletedAt.isNull());
    if (id != null && id.isNotEmpty) {
      return (consulta..where((f) => f.id.equals(id))).getSingleOrNull();
    }
    final filas = await consulta.get();
    return filas.length == 1 ? filas.single : null;
  }

  /// La fila entera con los nombres del cloud (la `sync_version` esperada de un `update` sale de acá).
  static Map<String, Object?> _payload({
    required String id,
    required Map<String, Object?> preferencias,
    required DateTime creada,
    required DateTime actualizada,
    required String? creadaPor,
    required int version,
  }) => {
    'id': id,
    'notif_preferences': preferencias,
    'created_at': creada.toUtc().toIso8601String(),
    'updated_at': actualizada.toUtc().toIso8601String(),
    'created_by': creadaPor,
    'deleted_at': null,
    'sync_version': version,
  };
}

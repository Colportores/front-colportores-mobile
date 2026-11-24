import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../mapa/data/services/house_status_updater_drift.dart';

/// Vuelve a calcular el color de la casa de cada cobro **anulado** que bajó del servidor (HU-COB-006,
/// vista 30B-05; decisión de Cristian, 23/11, «Anul. al tel», backend-supabase#306).
///
/// Caso: Marta anula desde el panel un cobro de Ana que dejaba la venta saldada. Cuando Ana sincroniza,
/// el cobro llega anulado y el saldo de la venta vuelve solo (sale de `CobroValido`, que ya no lo
/// cuenta). La casa, en cambio, tiene su color guardado en `house_status` (ADR-003, R-UB08): sin este
/// paso seguiría pintada como «venta completa» con plata por cobrar. `HouseStatusUpdaterDrift` es la
/// única que escribe esa cache, así que se le pide a ella.
///
/// Lo anulado que Ana hizo desde su teléfono baja de vuelta igual: la casa ya estaba recalculada, y el
/// updater no escribe ni encola nada si el color no cambia.
///
/// **No lanza.** Corre después de que el delta se confirmó (`DriftLocalStore`): si algo falla, el cobro
/// ya quedó anulado en el teléfono y lo único que se atrasa es el color de esa casa hasta el próximo
/// cambio que la toque. Se anota en el log, sin datos del cliente.
final class CasasDeCobrosBajados {
  /// [_encolador] y [_ahora] se pasan como `encolador:` y `ahora:`.
  CasasDeCobrosBajados(this._db, {required this._encolador, DateTime Function()? ahora})
    : _ahora = ahora ?? (() => DateTime.now().toUtc());

  final AppDatabase _db;
  final EncoladorSync _encolador;
  final DateTime Function() _ahora;

  /// Recibe las filas del delta (`entidad` → filas del servidor) y recalcula las casas de los cobros
  /// anulados que trae. Un cobro cuya venta, vínculo o ubicación no están en el teléfono se salta: no
  /// hay casa que pintar.
  Future<void> call(Map<String, List<Map<String, Object?>>> filas) async {
    try {
      final ids = [
        for (final fila in filas['cobranza'] ?? const <Map<String, Object?>>[])
          if (fila['anulado_at'] != null && fila['id'] != null) '${fila['id']}',
      ];
      if (ids.isEmpty) return;
      final casas = await _casasDe(ids);
      final ahora = _ahora();
      for (final casa in casas) {
        await HouseStatusUpdaterDrift(
          _db,
          encolador: _encolador,
        ).recalcular(casa.ubicacionId, ahora: ahora, colportorId: casa.colportorId);
      }
    } on Object catch (e, st) {
      AppLogger.instance.error(
        LogModulo.sync,
        'COLOR_TRAS_ANULACION_FAIL',
        'no se pudo recalcular el color de la casa de un cobro anulado que bajó',
        const {},
        e,
        st,
      );
    }
  }

  /// Las casas (ubicación + quién vendió) de los cobros [ids], sin repetir.
  Future<List<({String ubicacionId, String colportorId})>> _casasDe(List<String> ids) async {
    final casas = <String, String>{};
    for (var i = 0; i < ids.length; i += 500) {
      final tramo = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final consulta =
          _db.selectOnly(_db.cobranzas).join([
              innerJoin(_db.ventas, _db.ventas.id.equalsExp(_db.cobranzas.ventaId)),
              innerJoin(
                _db.espacioPersonas,
                _db.espacioPersonas.id.equalsExp(_db.ventas.espacioPersonaId),
              ),
              innerJoin(_db.espacios, _db.espacios.id.equalsExp(_db.espacioPersonas.espacioId)),
            ])
            ..addColumns([_db.espacios.ubicacionId, _db.ventas.colportorId])
            ..where(_db.cobranzas.id.isIn(tramo));
      for (final fila in await consulta.get()) {
        final ubicacionId = fila.read(_db.espacios.ubicacionId);
        final colportorId = fila.read(_db.ventas.colportorId);
        if (ubicacionId != null && colportorId != null) casas[ubicacionId] = colportorId;
      }
    }
    return [for (final e in casas.entries) (ubicacionId: e.key, colportorId: e.value)];
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../data/datasources/ubicacion_local_data_source_drift.dart';
import 'alta_ubicacion_providers.dart' show relojAltaUbicacionProvider;

/// Quién deshace las uniones de duplicados que el servidor rechazó (#679): el DAO de ubicaciones, con
/// el encolador del motor (el `update` de A cuando vuelve a casa). `null` sin la DB abierta.
final deshacedorDeUnionesProvider = Provider.autoDispose<UbicacionLocalDataSourceDrift?>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return null;
  return UbicacionLocalDataSourceDrift(db, encolador: ref.watch(encoladorSyncProvider));
});

/// HU-UBI-006, «el servidor rechaza el trabajo» (decisión de Cristian, 10/11, «Unión rech.»: «queda
/// separado en el teléfono»; #679): con la app abierta, cada vez que un trabajo «marcar como
/// duplicado» vuelve `INVALID` (lo marque el motor en esta app o en segundo plano), la unión se deshace
/// en el teléfono y el par vuelve a «Posibles duplicados» con su aviso. Al abrir la app se deshace lo
/// que haya quedado pendiente.
///
/// Las vueltas no se pisan: si llega otro aviso mientras corre una, se corre otra al terminar. Si
/// deshacer falla, queda en el log y se reintenta la próxima vez que cambie la cola o se abra la app.
final unionesRechazadasProvider = Provider.autoDispose<void>((ref) {
  final fuente = ref.watch(deshacedorDeUnionesProvider);
  if (fuente == null) return;
  final reloj = ref.watch(relojAltaUbicacionProvider);
  final log = AppLogger.instance;
  var corriendo = false;
  var otraVez = false;
  var vivo = true;
  ref.onDispose(() => vivo = false);

  Future<void> deshacer() async {
    if (corriendo) {
      otraVez = true;
      return;
    }
    corriendo = true;
    try {
      do {
        otraVez = false;
        for (final u in await fuente.deshacerUnionesRechazadas(ahora: reloj())) {
          log.info(LogModulo.db, 'UBICACION_UNION_DESHECHA', 'el servidor rechazó la unión', {
            'conservada_id': u.conservadaId,
            'duplicada_id': u.duplicadaId,
            'codigo': u.codigo,
            'duplicada_reactivada': u.duplicadaReactivada,
            'conservada_a_casa': u.conservadaVolvioACasa,
            'sin_volver': u.sinVolver,
          });
        }
      } while (otraVez && vivo);
    } on Object catch (e, st) {
      // Nunca la excepción al log (una `SqliteException` imprime la sentencia): solo su tipo.
      log.error(
        LogModulo.db,
        'UBICACION_UNION_DESHACER_FAIL',
        'no se pudo deshacer la unión rechazada',
        {'tipo': e.runtimeType.toString()},
        null,
        st,
      );
    } finally {
      corriendo = false;
    }
  }

  final suscripcion = fuente.observarUnionesPorDeshacer().listen(
    (cantidad) {
      if (cantidad > 0) unawaited(deshacer());
    },
    onError: (Object e) => log.error(
      LogModulo.db,
      'UBICACION_UNION_DESHACER_FAIL',
      'no se pudo leer qué uniones deshacer',
      {'tipo': e.runtimeType.toString()},
    ),
  );
  ref.onDispose(suscripcion.cancel);
});

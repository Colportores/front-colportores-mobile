// Quién es este dispositivo, para el sobre de §5.3.
//
// El `device_id` lo **genera el dispositivo** (decisión 2 del plan de sync) y
// se guarda en el Keystore la primera vez. Eso es lo que hace que exista antes
// del login —se puede encolar sin sesión y subir después— y que no dependa de
// la autenticación para que la sync ande.
//
// Que sea **estable entre arranques** no es un detalle de prolijidad: si
// cambiara en cada arranque, `sync.log` contaría un dispositivo nuevo por día
// y la telemetría por dispositivo de la Fase 3 no mediría nada. Y el trabajo en
// segundo plano corre en **otro isolate**, sin el estado de la app: si el id se
// generara en memoria, el ciclo de background se reportaría como otro teléfono.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sync_engine/sync_engine.dart';

const _idEnKeystore = 'colportaje.device.id';

/// La versión de la app que se reporta en el sobre.
///
/// Constante y no leída de `package_info_plus`: es telemetría y no decide nada
/// —lo que corta un push viejo es `schema_version`— así que no justifica un
/// plugin más, que además habría que inicializar también en el isolate de
/// segundo plano.
const versionDeLaApp = '0.9.2-banco';

/// El sobre de este dispositivo. Estable entre arranques y entre isolates.
Future<ClientEnvelope> sobreDeEsteDispositivo() async {
  const almacen = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  var id = await almacen.read(key: _idEnKeystore);
  if (id == null) {
    // UUID v7: el mismo generador que usan las PKs. Ordenable por tiempo, que
    // acá no hace falta pero tampoco molesta, y ya está en el motor.
    id = UuidV7().next();
    await almacen.write(key: _idEnKeystore, value: id);
  }

  return ClientEnvelope(deviceId: id, appVersion: versionDeLaApp);
}

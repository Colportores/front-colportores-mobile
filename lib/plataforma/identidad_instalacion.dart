import 'package:sync_engine/sync_engine.dart';

import '../core/secure_storage/almacen_seguro.dart';

/// La versión de la app que viaja en el sobre del sync (§5.3). Es solo para leer la telemetría de
/// `sync.log`: lo que corta un push viejo es la versión del formato de cable, no esta. Entra por
/// `--dart-define=APP_VERSION=…` en el build de release.
const versionApp = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// El id de **esta instalación** (§5.3): no el del colportor ni el del hardware.
///
/// Se genera la primera vez y queda en el almacén seguro ([ClaveSegura.idInstalacion]). Existe
/// antes del login, que es lo que deja encolar sin sesión y subir después. Una reinstalación, o el
/// borrado de datos locales (HU-AUTH-010), estrena uno nuevo, y está bien: la réplica también
/// arranca de cero.
///
/// Si el almacén falla, el sobre sale con un id de esta ejecución y no se guarda: el sync no se
/// frena por la telemetría, y la próxima apertura vuelve a intentar guardarlo.
Future<ClientEnvelope> sobreDeEstaInstalacion(AlmacenSeguro almacen, {UuidV7? uuid}) async {
  String? id;
  try {
    id = await almacen.leer(ClaveSegura.idInstalacion);
    if (id == null) {
      id = (uuid ?? UuidV7()).next();
      await almacen.escribir(ClaveSegura.idInstalacion, id);
    }
  } on AlmacenSeguroException {
    id ??= (uuid ?? UuidV7()).next();
  }
  return ClientEnvelope(deviceId: id, appVersion: versionApp);
}

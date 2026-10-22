// El sobre del sync (contrato-sync-engine §5.3) identifica a la instalación: el mismo id en cada
// arranque, y un id nuevo solo cuando el teléfono arranca de cero.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/plataforma/identidad_instalacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la primera vez genera el id y lo guarda; después devuelve el mismo', () async {
    final almacen = AlmacenSeguroEnMemoria();

    final primero = await sobreDeEstaInstalacion(almacen);
    final segundo = await sobreDeEstaInstalacion(almacen);

    expect(primero.deviceId, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-')));
    expect(almacen.contenido[ClaveSegura.idInstalacion], primero.deviceId);
    expect(segundo.deviceId, primero.deviceId);
    expect(primero.appVersion, versionApp);
  });

  test('si el almacén falla, el sync no se frena: sale con un id de esta ejecución', () async {
    final almacen = AlmacenSeguroEnMemoria()..simularFalla = true;

    final sobre = await sobreDeEstaInstalacion(almacen);

    expect(sobre.deviceId, isNotEmpty);
  });
}

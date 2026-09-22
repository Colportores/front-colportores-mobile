// Un solo caso y archivo propio a propósito: `drift_flutter` resuelve el directorio temporal de
// sqlite **una vez por isolate** (su bandera `hasConfiguredSqlite`), y `flutter test` corre cada
// archivo en un isolate propio. Acompañado de otros tests, la primera apertura se comería esa
// resolución y este caso probaría otra cosa.
//
// Lo que se prueba: cuando el que falla es el propio opener de `driftDatabase` —y no una query—,
// cerrar esa DB a medio abrir relanza la misma falla. Si la destrucción de la clave no pasa por un
// `finally`, la clave sobrevive al intento fallido (en memoria, con la sesión ya caída) y escapa la
// excepción cruda en vez de la tipada.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

void main() {
  test('cuando el opener de Drift falla, destruye la clave y lanza DbLocalException', () async {
    final directorio = await Directory.systemTemp.createTemp('colportores_db_opener_test');
    addTearDown(() => directorio.delete(recursive: true));
    final helper = DatabaseHelper(
      directorio: () async => directorio,
      directorioTemporal: () async => throw const FileSystemException('sin directorio temporal'),
      logger: loggerMudo(),
    );
    final clave = ClaveDb(Uint8List.fromList(List<int>.filled(32, 1)));

    // Drift arranca la apertura sin nadie escuchando todavía (`DatabaseConnection.delayed`), así
    // que la falla del opener queda además como error suelto en la zona. Es de Drift y no del
    // helper, pero sin zona propia tumbaría el caso antes de poder mirar lo que importa.
    Object? capturada;
    await runZonedGuarded(() async {
      try {
        await helper.abrir(clave);
      } on Object catch (e) {
        capturada = e;
      }
    }, (_, _) {});

    expect(capturada, isA<DbLocalException>().having((e) => e.operacion, 'operacion', 'abrir'));
    expect(helper.abierta, isFalse);
    expect(clave.destruida, isTrue, reason: 'la clave no sobrevive al fallo del opener');
    expect(await helper.existe(), isFalse, reason: 'el archivo no se llegó a crear');
  });
}

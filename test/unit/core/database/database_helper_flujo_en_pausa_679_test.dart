// #679: cerrar la DB con un flujo de Drift en pausa (Riverpod pausa los providers de las pantallas
// tapadas). `close()` de Drift espera el «done» de cada suscriptor y uno en pausa no lo recibe: el
// cierre de sesión quedaba colgado con la DB abierta.
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directorio;
  late DatabaseHelper helper;

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('colportores_679_helper');
    helper = DatabaseHelper(
      directorio: () async => directorio,
      directorioTemporal: () async => directorio,
      logger: loggerMudo(),
    );
  });

  tearDown(() async {
    await helper.cerrar().timeout(const Duration(seconds: 2), onTimeout: () {});
    await directorio.delete(recursive: true);
  });

  test('cerrar() no se queda esperando a un flujo de Drift en pausa', () async {
    final db = await helper.abrir(ClaveDb(Uint8List.fromList(List<int>.filled(32, 4))));
    final suscripcion = db.select(db.ubicaciones).watch().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    suscripcion.pause();

    await expectLater(
      helper.cerrar().timeout(const Duration(seconds: 5)),
      completes,
      reason: 'el cierre no depende de que el flujo pausado se reanude',
    );
    expect(helper.abierta, isFalse);
    await suscripcion.cancel();
  });

  test('con el flujo en pausa, la DB se vuelve a abrir después del cierre', () async {
    final clave = Uint8List.fromList(List<int>.filled(32, 4));
    final db = await helper.abrir(ClaveDb(Uint8List.fromList(clave)));
    final suscripcion = db.select(db.ubicaciones).watch().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    suscripcion.pause();
    await helper.cerrar().timeout(const Duration(seconds: 5));

    final otra = await helper.abrir(ClaveDb(Uint8List.fromList(clave)));
    expect(await otra.select(otra.ubicaciones).get(), isEmpty);
    await suscripcion.cancel();
  });
}

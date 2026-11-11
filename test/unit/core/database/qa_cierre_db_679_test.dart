// QA de #679 (cerrar sesión no pasaba al login): casos límite del cierre de la DB que el test del
// implementador no cubre: dos cierres a la vez, un flujo pausado que se reanuda con la DB ya cerrada
// y reabierta, muchos flujos pausados y la reapertura con la cola del motor.
import 'dart:async';
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
  final clave = Uint8List.fromList(List<int>.filled(32, 4));

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('colportores_679_qa');
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

  test('dado un flujo en pausa, cuando se cierra dos veces a la vez, ambos terminan y la DB '
      'queda cerrada', () async {
    final db = await helper.abrir(ClaveDb(Uint8List.fromList(clave)));
    final s = db.select(db.ubicaciones).watch().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    s.pause();

    await Future.wait([helper.cerrar(), helper.cerrar()]).timeout(const Duration(seconds: 5));

    expect(helper.abierta, isFalse);
    await s.cancel();
  });

  test('dado un flujo en pausa, cuando se reanuda con la DB ya cerrada y reabierta, la DB nueva '
      'sigue sirviendo y no queda un error sin atrapar', () async {
    final db = await helper.abrir(ClaveDb(Uint8List.fromList(clave)));
    final errores = <Object>[];
    final s = db.select(db.ubicaciones).watch().listen((_) {}, onError: errores.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    s.pause();
    await helper.cerrar().timeout(const Duration(seconds: 5));
    final otra = await helper.abrir(ClaveDb(Uint8List.fromList(clave)));

    s.resume();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(await otra.select(otra.ubicaciones).get(), isEmpty);
    await s.cancel();
  });

  test('dado 20 flujos en pausa sobre dos tablas, cuando se cierra, termina a tiempo', () async {
    final db = await helper.abrir(ClaveDb(Uint8List.fromList(clave)));
    final subs = <StreamSubscription<Object?>>[];
    for (var i = 0; i < 10; i++) {
      subs
        ..add(db.select(db.ubicaciones).watch().listen((_) {}))
        ..add(db.select(db.syncQueue).watch().listen((_) {}));
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    for (final s in subs) {
      s.pause();
    }

    await helper.cerrar().timeout(const Duration(seconds: 5));

    expect(helper.abierta, isFalse);
    for (final s in subs) {
      await s.cancel();
    }
  });

  test('dado un cierre con un flujo en pausa, cuando se abre otra vez, la cola del motor guarda '
      'y lee un trabajo de unión (la conexión se soltó de verdad)', () async {
    final db = await helper.abrir(ClaveDb(Uint8List.fromList(clave)));
    final s = db.select(db.syncQueue).watch().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    s.pause();
    await helper.cerrar().timeout(const Duration(seconds: 5));

    final otra = await helper.abrir(ClaveDb(Uint8List.fromList(clave)));
    await otra.customStatement(
      'INSERT INTO sync_queue (id, client_op_id, entity, op, payload, row_pk, created_at, state) '
      "VALUES ('q-1', 'op-1', 'ubicacion', 'marcar_como_duplicado', '{}', 'ub-b', 1, 'PENDING')",
    );
    expect(await otra.select(otra.syncQueue).get(), hasLength(1));
    await s.cancel();
  });
}

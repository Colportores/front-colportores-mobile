// AppDatabase en memoria (sin cifrado): lo que se verifica acá es el esquema y el log de
// migraciones; el cifrado se prueba en database_helper_test.dart.
import 'dart:io';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  group('AppDatabase', () {
    late _SalidaEnMemoria salida;
    late AppDatabase db;

    setUp(() {
      salida = _SalidaEnMemoria();
      db = AppDatabase(NativeDatabase.memory(), logger: AppLogger(output: salida));
    });

    tearDown(() => db.close());

    test('dado una DB nueva, cuando abre, fija user_version en schemaVersion', () async {
      final fila = await db.customSelect('PRAGMA user_version').getSingle();

      expect(fila.read<int>('user_version'), db.schemaVersion);
      expect(db.schemaVersion, 1);
    });

    test('dado una DB nueva, cuando abre, loguea DB_CREADA con la versión', () async {
      await db.customSelect('SELECT 1').get();

      expect(salida.lineas, ['[INFO][DB][DB_CREADA] esquema inicial creado — {"version":1}']);
    });

    test('dado una DB ya creada, cuando se vuelve a abrir, no loguea nada', () async {
      // Sobre archivo y no en memoria: lo que se prueba es abrir de nuevo la misma DB, y una DB en
      // memoria deja de existir al cerrarla (dos queries sobre la misma instancia no prueban nada).
      final directorio = await Directory.systemTemp.createTemp('colportores_app_database_test');
      addTearDown(() => directorio.delete(recursive: true));
      final archivo = File('${directorio.path}/prueba.sqlite');
      final primera = AppDatabase(NativeDatabase(archivo), logger: AppLogger(output: salida));
      await primera.customSelect('SELECT 1').get();
      await primera.close();
      salida.lineas.clear();

      final segunda = AppDatabase(NativeDatabase(archivo), logger: AppLogger(output: salida));
      addTearDown(segunda.close);
      await segunda.customSelect('SELECT 1').get();

      expect(salida.lineas, isEmpty);
    });
  });
}

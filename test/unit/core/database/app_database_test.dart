// AppDatabase en memoria (sin cifrado): lo que se verifica acá es el esquema y el log de
// migraciones; el cifrado se prueba en database_helper_test.dart.
import 'dart:io';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:drift/drift.dart' show QueryRow;
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
      expect(db.schemaVersion, 2);
      expect(AppDatabase.versionEsquema, db.schemaVersion);
    });

    test('dado una DB nueva, cuando abre, crea la tabla jornada y su índice', () async {
      expect(await _esquema(db), containsAll(['table jornada', 'index jornada_colportor_idx']));
    });

    test('dado una DB nueva, cuando abre, loguea DB_CREADA con la versión', () async {
      await db.customSelect('SELECT 1').get();

      expect(salida.lineas, ['[INFO][DB][DB_CREADA] esquema inicial creado — {"version":2}']);
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

  group('AppDatabase — migración 1 → 2', () {
    // Una DB de la versión 1 es un archivo sin tablas con `user_version = 1` (#6). El `setup` corre
    // antes de que Drift lea la versión, así que Drift la ve como una DB existente a migrar.
    AppDatabase deVersion1(LogOutput salida) => AppDatabase(
      NativeDatabase.memory(setup: (raw) => raw.execute('PRAGMA user_version = 1')),
      logger: AppLogger(output: salida),
    );

    test('dado una DB en versión 1, cuando abre, crea jornada, queda en versión 2 y loguea la '
        'migración', () async {
      final salida = _SalidaEnMemoria();
      final db = deVersion1(salida);
      addTearDown(db.close);

      final fila = await db.customSelect('PRAGMA user_version').getSingle();

      expect(fila.read<int>('user_version'), 2);
      expect(await _esquema(db), containsAll(['table jornada', 'index jornada_colportor_idx']));
      expect(salida.lineas, ['[INFO][DB][MIGRATION] migración ejecutada — {"from":1,"to":2}']);
    });

    test('dado una DB migrada desde la versión 1, cuando se compara con una DB nueva, el esquema '
        'es idéntico', () async {
      // Detecta un paso que falla o deja un esquema distinto desde la 1, pero no un paso `N → N+1`
      // olvidado ni tolera un `ADD COLUMN` (compara texto). TODO(#70): congelar la v2 con
      // `drift_dev make-migrations` y usar `SchemaVerifier` — bloqueado por tooling, ver
      // `AppDatabase.migration`. No copiar este test para la versión 3.
      final migrada = deVersion1(_SalidaEnMemoria());
      final nueva = AppDatabase(
        NativeDatabase.memory(),
        logger: AppLogger(output: _SalidaEnMemoria()),
      );
      addTearDown(migrada.close);
      addTearDown(nueva.close);

      expect(await _sqlDelEsquema(migrada), await _sqlDelEsquema(nueva));
    });
  });
}

/// Tablas e índices propios de la DB (sin los internos de SQLite), ordenados.
Future<List<QueryRow>> _maestro(AppDatabase db) => db
    .customSelect(
      "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    )
    .get();

/// `tipo nombre` de cada objeto del esquema (`table jornada`, `index …`).
Future<List<String>> _esquema(AppDatabase db) async => [
  for (final fila in await _maestro(db))
    '${fila.read<String>('type')} ${fila.read<String>('name')}',
];

/// El `CREATE …` de cada objeto del esquema.
Future<List<String>> _sqlDelEsquema(AppDatabase db) async => [
  for (final fila in await _maestro(db)) fila.read<String>('sql'),
];

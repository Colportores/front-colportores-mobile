// El backup E2E exporta la DB local (HU-SYNC-005, ADR-006): lo que no se puede volver a bajar del
// servidor, completo o desde un instante, y la cola de sync. De punta a punta: la DB exportada,
// comprimida y cifrada con la DEK por el motor de backup, vuelve a ser la misma al descifrarla.
import 'dart:convert';
import 'dart:typed_data';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/drift_snapshot.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/respaldo/data/services/crypto_con_dek.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/logger_mudo.dart';

Map<String, Object?> _jornada(String id, String actualizada) => {
  'id': id,
  'colportor_id': 'col-1',
  'inicio': '2026-10-16T08:00:00.000Z',
  'fin': null,
  'acompaniante_id': null,
  'tipo_acompaniamiento': null,
  'total_visitas': 7,
  'total_ventas': 2,
  'created_at': '2026-10-16T08:00:00.000Z',
  'updated_at': actualizada,
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 1,
};

Map<String, Object?> _producto(String id) => {
  'id': id,
  'nombre': 'Libro $id',
  'descripcion': null,
  'tipo': 'LIBRO',
  'es_bonificable': true,
  'es_misionero': false,
  'precio_base_compra': 18000,
  'casa_editora': null,
  'imagen_url': null,
  'created_at': '2026-10-20T12:00:00+00:00',
  'updated_at': '2026-10-20T12:00:00+00:00',
  'created_by': null,
  'deleted_at': null,
  'sync_version': 1,
};

Map<String, Object?> _tabla(Map<String, Object?> payload, String nombre) =>
    ((payload['tablas']! as Map<String, Object?>)[nombre]! as Map).cast<String, Object?>();

List<Map<String, Object?>> _filas(Map<String, Object?> payload, String nombre) =>
    ((_tabla(payload, nombre)['filas']! as List).cast<Map<String, Object?>>());

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftSnapshot snapshot;
  late DriftLocalStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
    snapshot = DriftSnapshot(
      db,
      tablas: entidadesDelBackup,
      clock: () => DateTime.utc(2026, 11, 2, 22),
    );
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> exportar({DateTime? since}) async =>
      jsonDecode(utf8.decode(await snapshot.export(since: since))) as Map<String, Object?>;

  Future<void> sembrar() async {
    await store.applyDelta(
      {
        'jornada': [
          _jornada('jor-vieja', '2026-10-16T08:00:00.000Z'),
          _jornada('jor-nueva', '2026-11-02T20:00:00.000Z'),
        ],
        'producto': [_producto('pro-1')],
      },
      scope: 'mirror',
      watermark: null,
    );
    await db
        .into(db.personas)
        .insert(
          PersonasCompanion.insert(
            id: 'per-1',
            nombre: 'Ana',
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        );
    await DriftJobStore(db).append(
      SyncJob(
        clientOpId: 'op-1',
        entity: 'jornada',
        op: Op.insert,
        payload: const {'id': 'jor-nueva'},
        createdAt: DateTime.utc(2026, 11, 2, 20),
        rowPk: 'jor-nueva',
      ),
    );
    await db
        .into(db.auditLogLocal)
        .insert(
          AuditLogLocalCompanion.insert(
            evento: EventoAuditoriaLocal.clickToCall,
            uuid: 'per-1',
            creadoEn: DateTime.utc(2026, 10, 1),
          ),
        );
  }

  group('qué entra', () {
    test('lo que no se puede bajar del servidor y la cola; no las réplicas ni la sesión', () async {
      await sembrar();

      final payload = await exportar();

      final tablas = (payload['tablas']! as Map).keys;
      expect(tablas, containsAll(['jornada', 'persona', 'audit_log', 'sync_queue']));
      expect(tablas, isNot(contains('producto')), reason: 'el pull la reconstruye');
      expect(tablas, isNot(contains('sesion_usuario')), reason: 'es de la sesión del teléfono');
      expect(tablas, isNot(contains('sync_watermark')));
      expect(tablas, isNot(contains('sync_meta')));
      expect(
        _filas(payload, 'persona').single['nombre'],
        'Ana',
        reason: 'la persona solo sale por el backup E2E (Ley 18.331)',
      );
      expect(
        _filas(payload, 'sync_queue').single['client_op_id'],
        'op-1',
        reason: 'los jobs encolados vuelven a existir tras un restore (§7, fase 1)',
      );
    });

    test('todas las tablas de la DB están decididas: entra o se deja afuera a propósito', () {
      final todas = db.allTables.map((t) => t.actualTableName).toSet();
      final replicas = {
        for (final s in specsDeLaApp)
          if (s.policy == SyncPolicy.pull) s.entity,
      };

      final sinDecidir = todas.difference(entidadesDelBackup).difference(replicas).difference({
        'sesion_usuario',
        ...tablasDelMotor.difference({'sync_queue'}),
      });

      expect(
        sinDecidir,
        isEmpty,
        reason: 'una tabla nueva con datos del colportor no puede quedar sin backup en silencio',
      );
    });

    test('el payload dice el formato, la versión del esquema y cuándo se leyó', () async {
      final payload = await exportar();

      expect(payload['formato'], DriftSnapshot.formato);
      expect(payload['esquema'], db.schemaVersion);
      expect(payload['exportadoEn'], '2026-11-02T22:00:00.000Z');
      expect(payload['completo'], isTrue);
      expect(payload['desde'], isNull);
    });
  });

  group('completo e incremental', () {
    test('el completo lleva todas las filas', () async {
      await sembrar();

      final payload = await exportar();

      expect(
        _filas(payload, 'jornada').map((f) => f['id']),
        unorderedEquals(['jor-vieja', 'jor-nueva']),
      );
      expect(_tabla(payload, 'jornada')['modo'], 'upsert');
    });

    test('el incremental lleva solo lo escrito desde el instante, y la cola entera', () async {
      await sembrar();

      final payload = await exportar(since: DateTime.utc(2026, 11, 1));

      expect(payload['completo'], isFalse);
      expect(payload['desde'], '2026-11-01T00:00:00.000Z');
      expect(_filas(payload, 'jornada').map((f) => f['id']), ['jor-nueva']);
      expect(_filas(payload, 'persona'), isEmpty);
      expect(
        _tabla(payload, 'sync_queue')['modo'],
        'replace',
        reason: 'sin fecha de escritura no se sabe qué cambió: va entera y reemplaza',
      );
      expect(_filas(payload, 'sync_queue'), hasLength(1));
    });

    test('el límite es inclusivo: una fila escrita en el mismo instante no se pierde', () async {
      await sembrar();

      final payload = await exportar(since: DateTime.utc(2026, 11, 2, 20));

      expect(_filas(payload, 'jornada').map((f) => f['id']), ['jor-nueva']);
    });

    test('el audit_log se corta por creado_en', () async {
      await sembrar();
      await db
          .into(db.auditLogLocal)
          .insert(
            AuditLogLocalCompanion.insert(
              evento: EventoAuditoriaLocal.clickToCall,
              uuid: 'per-1',
              motivo: const Value('x'),
              creadoEn: DateTime.utc(2026, 11, 2, 21),
            ),
          );

      final payload = await exportar(since: DateTime.utc(2026, 11, 1));

      expect(_filas(payload, 'audit_log'), hasLength(1));
    });

    test('un incremental sin cambios es chico y válido', () async {
      final payload = await exportar(since: DateTime.utc(2026, 12, 1));

      expect(_filas(payload, 'jornada'), isEmpty);
      expect(_filas(payload, 'persona'), isEmpty);
    });
  });

  test('las filas van crudas: las fechas son epoch ms, como en la DB', () async {
    await sembrar();

    final jornada = _filas(await exportar(), 'jornada').firstWhere((f) => f['id'] == 'jor-nueva');

    expect(jornada['updated_at'], DateTime.utc(2026, 11, 2, 20).millisecondsSinceEpoch);
  });

  test('restore todavía no existe (HU-SYNC-006): falla a propósito, no aplica a medias', () {
    expect(() => snapshot.restore([utf8.encode('{}')]), throwsUnsupportedError);
  });

  group('de punta a punta con el motor de backup', () {
    late FakeArchive drive;
    late BackupService servicio;
    late DateTime ahora;

    setUp(() {
      ahora = DateTime.utc(2026, 11, 2, 22);
      drive = FakeArchive(authorized: true, clock: () => ahora, informaHashRemoto: true);
      servicio = BackupService(
        archive: drive,
        crypto: CryptoConDek(
          () async => ClaveDb(Uint8List.fromList(List<int>.generate(32, (i) => i))),
        ),
        snapshot: DriftSnapshot(db, tablas: entidadesDelBackup, clock: () => ahora),
        clock: () => ahora,
      );
    });

    test('lo que sale a Drive va cifrado: no tiene nada legible de la DB', () async {
      await sembrar();

      await servicio.backupNow(watermark: 'w-1');

      final subido = utf8.decode(
        await drive.download(drive.entries.single.id),
        allowMalformed: true,
      );
      expect(subido, isNot(contains('Ana')));
      expect(subido, isNot(contains('jor-nueva')));
    });

    test('con la misma DEK se descifra y es lo exportado; con otra, no', () async {
      await sembrar();
      await servicio.backupNow(watermark: 'w-1');
      final blob = await drive.download(drive.entries.single.id);

      final mismaDek = CryptoConDek(
        () async => ClaveDb(Uint8List.fromList(List<int>.generate(32, (i) => i))),
      );
      final claro = jsonDecode(utf8.decode(await mismaDek.decrypt(blob))) as Map<String, Object?>;
      expect(_filas(claro, 'persona').single['nombre'], 'Ana');

      final otraDek = CryptoConDek(() async => ClaveDb(Uint8List(32)..fillRange(0, 32, 9)));
      await expectLater(otraDek.decrypt(blob), throwsA(anything));
    });

    test('el incremental parte de cuándo se leyó la base, y la cadena se verifica', () async {
      await sembrar();
      await servicio.backupNow(watermark: 'w-1');
      ahora = ahora.add(const Duration(hours: 24));
      await store.applyDelta(
        {
          'jornada': [_jornada('jor-nueva-2', '2026-11-03T21:00:00.000Z')],
        },
        scope: 'mirror',
        watermark: null,
      );

      final inc = await servicio.backupNow(watermark: 'w-2');

      expect(inc.parentId, isNotNull);
      final claro =
          jsonDecode(
                utf8.decode(
                  await CryptoConDek(
                    () async => ClaveDb(Uint8List.fromList(List<int>.generate(32, (i) => i))),
                  ).decrypt(await drive.download(inc.id)),
                ),
              )
              as Map<String, Object?>;
      expect(claro['completo'], isFalse);
      expect(claro['desde'], '2026-11-02T22:00:00.000Z');
      expect(_filas(claro, 'jornada').map((f) => f['id']), ['jor-nueva-2']);
      expect((await servicio.verifyIntegrity()).ok, isTrue);
    });

    test('sin DEK (sin sesión, almacén que falla) no sube nada', () async {
      await sembrar();
      final sinDek = BackupService(
        archive: drive,
        crypto: CryptoConDek(() async => null),
        snapshot: snapshot,
      );

      await expectLater(sinDek.backupNow(), throwsStateError);

      expect(drive.entries, isEmpty);
    });

    test('la DEK se destruye después de cada operación', () async {
      final claves = <ClaveDb>[];
      final cripto = CryptoConDek(() async {
        final c = ClaveDb(Uint8List.fromList(List<int>.generate(32, (i) => i)));
        claves.add(c);
        return c;
      });

      await cripto.encrypt(utf8.encode('{}'));

      expect(claves.single.destruida, isTrue);
    });
  });
}

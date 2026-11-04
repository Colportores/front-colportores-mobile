// I3 (#183): el flujo de la demo del Hito 3, de punta a punta con el código real de la app (los DAOs
// escriben en la DB Drift, el motor sube por el transporte) y con los ids que genera el teléfono de
// verdad: UUID v7. Los demás tests de esta carpeta usan ids de mentira (`ub-1`, `jor-1`) porque el
// servidor falso los acepta; el real los rechaza (`(payload ->> pk)::uuid`).
//
// Lo que se prueba acá es la forma de lo que sube: cada job lleva ids que son UUID, ningún dato
// personal, y ningún job nombra una fila cuyo alta viaja después (el servidor comprueba cada FK en el
// momento, `23503`, y el servidor falso no).
//
// Contra el servidor de verdad (migraciones del backend) el mismo día corre en
// `sync_contra_base_real_test.dart`.
import 'dart:convert';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/dia_de_trabajo.dart';
import '../../helpers/logger_mudo.dart';

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// Lo que graba el transporte: el cuerpo del lote tal como sale por el cable.
final class _Grabadora implements SyncTransport {
  _Grabadora(this._servidor);

  final FakeSyncTransport _servidor;
  final cuerpos = <Map<String, Object?>>[];

  static const sobre = ClientEnvelope(
    deviceId: '01920000-0000-7000-8000-00000000d001',
    appVersion: '0.0.0-test',
  );

  @override
  Future<PushResult> push(PushBatch batch) {
    cuerpos.add(pushRequestToJson(batch, sobre));
    return _servidor.push(batch);
  }

  @override
  Future<PullDelta> pull({required List<String> entities, String? watermark, int? limit}) =>
      _servidor.pull(entities: entities, watermark: watermark, limit: limit);

  Iterable<Map<String, Object?>> get jobs => [
    for (final c in cuerpos)
      for (final j in c['jobs']! as List<Object?>) j! as Map<String, Object?>,
  ];
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeSyncTransport servidor;
  late _Grabadora cable;
  late SyncEngine motor;
  late DiaDeTrabajo dia;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport(pkFieldPorEntidad: const {'house_status': 'ubicacion_id'});
    cable = _Grabadora(servidor);
    motor = SyncEngine(
      specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
      transport: cable,
      jobs: DriftJobStore(db),
      store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
    );
    dia = DiaDeTrabajo(db, motor, inicio: DateTime.utc(2026, 10, 30, 12));
  });
  tearDown(() async {
    await motor.dispose();
    await db.close();
  });

  Future<void> diaDeTrabajo() => dia.correrTodo();

  test(
    'el día de trabajo sin señal sube entero al volver la red, sin conflictos ni rechazos',
    () async {
      servidor.offline();
      await diaDeTrabajo();
      expect((await motor.syncNow()).ok, isFalse, reason: 'sin red nada se pierde: queda en cola');
      expect((await DriftJobStore(db).status()).pending, greaterThan(0));

      servidor.online();
      final resultado = await motor.syncNow();

      expect(resultado.ok, isTrue);
      expect(resultado.conflicts, 0);
      expect(resultado.invalidated, 0);
      expect((await DriftJobStore(db).status()).pending, 0);
      for (final entidad in [
        'jornada',
        'ubicacion',
        'espacio',
        'espacio_persona',
        'agenda',
        'visita',
        'house_status',
      ]) {
        expect(servidor.rowsOf(entidad), hasLength(1), reason: entidad);
      }
      expect(servidor.rowsOf('jornada').single['fin'], isNotNull, reason: 'el cierre llegó');
    },
  );

  test('cada id que sube es un UUID, y las claves foráneas también', () async {
    await diaDeTrabajo();
    await motor.syncNow();

    const claves = {
      'id',
      'ubicacion_id',
      'espacio_id',
      'persona_id',
      'espacio_persona_id',
      'agenda_id',
      'visita_id',
      'jornada_id',
      'colportor_id',
      'ciudad_id',
      'created_by',
    };
    for (final job in cable.jobs) {
      final payload = job['payload']! as Map<String, Object?>;
      expect(job['client_op_id'], matches(_uuid), reason: '${job['entity']}: client_op_id');
      for (final c in claves.intersection(payload.keys.toSet())) {
        final v = payload[c];
        if (v == null) continue;
        expect(v, matches(_uuid), reason: '${job['entity']}.$c');
      }
    }
  });

  test('un padre sube antes que su hijo: el servidor tiene la FK resuelta en cada paso', () async {
    await diaDeTrabajo();
    await motor.syncNow();

    // El servidor aplica el lote en orden y cada FK se comprueba en el momento (`23503`): ningún job
    // puede nombrar una fila cuyo alta viaja después. La agenda que se agenda y más tarde se cumple
    // con una visita es el caso: su alta se funde con el cumplimiento y lleva `visita_id`.
    final jobs = cable.jobs.toList();
    final posicionDelAlta = <String, int>{
      for (final (i, j) in jobs.indexed)
        // house_status se identifica por la ubicación y nadie lo nombra.
        if (j['op'] == 'insert' && j['entity'] != 'house_status')
          '${(j['payload']! as Map<String, Object?>)['id']}': i,
    };
    for (final (i, j) in jobs.indexed) {
      final payload = j['payload']! as Map<String, Object?>;
      for (final MapEntry(:key, :value) in payload.entries) {
        final alta = posicionDelAlta['$value'];
        if (alta == null || alta == i) continue;
        expect(alta, lessThan(i), reason: '${j['entity']}.$key nombra un alta que sube después');
      }
    }
    final orden = [for (final j in jobs) '${j['entity']}'];
    expect(orden.indexOf('visita'), lessThan(orden.indexOf('agenda')));
  });

  test(
    'lo personal no sale del teléfono: ni la persona, ni su nota, ni el texto de la cita',
    () async {
      await diaDeTrabajo();
      await motor.syncNow();

      final enElCable = jsonEncode(cable.cuerpos);
      expect(enElCable, isNot(contains('Ana')));
      expect(enElCable, isNot(contains('Pérez')));
      expect(enElCable, isNot(contains('099123456')));
      expect(enElCable, isNot(contains('Atiende de tarde')));
      expect(servidor.rowsOf('persona'), isEmpty);
      expect(servidor.rowsOf('nota'), isEmpty);
    },
  );

  test('un reintento con los mismos lotes no duplica nada (client_op_id)', () async {
    await diaDeTrabajo();
    await motor.syncNow();
    final subidos = servidor.appliedOpIds.length;

    // El servidor aplicó el lote pero la respuesta se perdió: el motor lo vuelve a mandar.
    for (final cuerpo in cable.cuerpos) {
      final lote = pushRequestFromJson(cuerpo).batch;
      final repetido = await servidor.push(lote);
      expect(repetido.results.map((r) => r.outcome), everyElement(JobOutcome.duplicate));
    }

    expect(servidor.appliedOpIds, hasLength(subidos));
    expect(servidor.rowsOf('visita'), hasLength(1));
  });
}

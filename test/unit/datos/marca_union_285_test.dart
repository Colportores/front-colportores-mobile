// HU-UBI-006, «Marca unión» y «Marca local» (#285): `unida_a_id` llega con la ubicación en el pull y el
// teléfono la guarda en su tabla aparte `ubicacion_unida`, de solo bajada, que nunca sube. De ahí salen
// la leyenda «Unida a otra ubicación» de la Lista y la guarda de «Reactivar». Contra la DB real en
// memoria y el `DriftLocalStore` real.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/logger_mudo.dart';

Map<String, Object?> _fila(String id, {String? deletedAt, Object? unidaA = _sinClave}) => {
  'id': id,
  'tipo': 'CASA',
  'calle': 'Rivera',
  'numero': '1234',
  'lat': -34.9,
  'lon': -56.16,
  'ciudad_id': 'ciu-1',
  'zona_id': null,
  'created_at': '2026-11-04T12:00:00.000Z',
  'updated_at': '2026-11-04T12:00:00.000Z',
  'created_by': 'col-1',
  'deleted_at': deletedAt,
  'sync_version': 3,
  if (unidaA != _sinClave) 'unida_a_id': unidaA,
};

/// Marca para «la fila no trae la clave `unida_a_id`» (un servidor que todavía no la manda).
const _sinClave = Object();

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftLocalStore store;
  late UbicacionLocalDataSourceDrift local;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
    local = UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());
  });
  tearDown(() => db.close());

  Future<void> bajar(List<Map<String, Object?>> filas) =>
      store.applyDelta({'ubicacion': filas}, scope: 'ubicacion', watermark: 'w');

  Future<Map<String, String>> marcas() async => {
    for (final m in await db.select(db.ubicacionesUnidas).get()) m.ubicacionId: m.unidaAId,
  };

  group('la marca de unión baja con la ubicación y se guarda aparte', () {
    test('una ubicación unida del servidor deja su marca en la tabla local, y la fila de ubicacion '
        'no lleva la columna', () async {
      await bajar([
        _fila('ub-a', unidaA: null),
        _fila('ub-b', deletedAt: '2026-11-03T10:00:00.000Z', unidaA: 'ub-a'),
      ]);

      expect(await marcas(), {'ub-b': 'ub-a'});
      expect(
        (await db.select(db.ubicaciones).get()).map((u) => u.id),
        containsAll(['ub-a', 'ub-b']),
      );
    });

    test(
      'una fila posterior con unida_a_id nulo borra la marca; otra sin la clave no la toca',
      () async {
        await bajar([_fila('ub-b', deletedAt: '2026-11-03T10:00:00.000Z', unidaA: 'ub-a')]);

        await bajar([_fila('ub-b', deletedAt: '2026-11-03T10:00:00.000Z')]);
        expect(await marcas(), {'ub-b': 'ub-a'}, reason: 'sin la clave no se toca');

        await bajar([_fila('ub-b', unidaA: null)]);
        expect(await marcas(), isEmpty);
      },
    );

    test('una unión nueva del servidor pisa la marca anterior', () async {
      await bajar([_fila('ub-b', deletedAt: '2026-11-03T10:00:00.000Z', unidaA: 'ub-a')]);

      await bajar([_fila('ub-b', deletedAt: '2026-11-03T10:00:00.000Z', unidaA: 'ub-c')]);

      expect(await marcas(), {'ub-b': 'ub-c'});
    });

    test('la tabla es local: no es una entidad que escriba el motor ni que suba', () {
      expect(entidadesQueEscribeElMotor, isNot(contains('ubicacion_unida')));
    });
  });

  group('la Lista y «Reactivar» leen la marca', () {
    test('una baja unida que bajó del servidor, sin fila de auditoría local, no se reactiva y '
        'apunta a la conservada', () async {
      await bajar([
        _fila('ub-a', unidaA: null),
        _fila('ub-b', deletedAt: '2026-11-03T10:00:00.000Z', unidaA: 'ub-a'),
      ]);
      final b = (await local.obtener('ub-b'))!;

      await expectLater(
        local.cambiarBaja(
          'ub-b',
          baseUpdatedAt: b.auditoria.updatedAt,
          updatedAt: DateTime.utc(2026, 11, 4, 13),
          deletedAt: null,
        ),
        throwsA(
          isA<ReactivacionDeUnionException>().having((e) => e.conservadaId, 'conservadaId', 'ub-a'),
        ),
      );
      expect(
        (await local.obtener('ub-b'))!.auditoria.deletedAt,
        isNotNull,
        reason: 'sigue de baja',
      );
    });

    test(
      'la Lista muestra la baja como unida (motivo duplicado_de_<A>) y la activa sin motivo',
      () async {
        await bajar([
          _fila('ub-a', unidaA: null),
          _fila('ub-b', deletedAt: '2026-11-03T10:00:00.000Z', unidaA: 'ub-a'),
        ]);

        final lista = await local
            .observarListaDelColportor(colportorId: 'col-1', incluirBajas: true)
            .first;

        final porId = {for (final f in lista) f.ubicacion.id: f};
        expect(porId['ub-b']!.motivoBaja, 'duplicado_de_ub-a');
        expect(porId['ub-a']!.motivoBaja, isNull);
      },
    );

    test('una baja común del servidor (sin marca) se sigue reactivando', () async {
      await bajar([_fila('ub-c', deletedAt: '2026-11-03T10:00:00.000Z', unidaA: null)]);
      final c = (await local.obtener('ub-c'))!;

      final r = await local.cambiarBaja(
        'ub-c',
        baseUpdatedAt: c.auditoria.updatedAt,
        updatedAt: DateTime.utc(2026, 11, 4, 13),
        deletedAt: null,
      );

      expect(r.escribio, isTrue);
      expect(r.ubicacion.auditoria.deletedAt, isNull);
    });
  });
}

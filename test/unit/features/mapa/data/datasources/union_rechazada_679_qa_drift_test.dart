// QA de #679 («Unión rech.») contra la DB real en memoria: uniones encadenadas con una sola rechazada
// (la más vieja o la más nueva) y que deshacer no borre ninguna fila de lo que el colportor cargó.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/sync_queue_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/uniones_locales_table.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart' hide t0;
import '../../../../../helpers/duplicados_falsos.dart' show EncoladorMarcarDuplicadoFalso;
import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 13, 45, 10, 123);
  final tUnion = DateTime.utc(2026, 11, 2, 9, 0, 0, 250);
  final tUnion2 = DateTime.utc(2026, 11, 2, 9, 30);
  final tDeshacer = DateTime.utc(2026, 11, 2, 10);

  late AppDatabase db;
  late UbicacionLocalDataSourceDrift local;

  UbicacionModel ubicacion(String id, {TipoUbicacion tipo = TipoUbicacion.casa}) => UbicacionModel(
    id: id,
    tipo: tipo,
    calle: 'Av. Italia',
    numero: '1234',
    lat: -34.891,
    lon: -56.125,
    ciudadId: 'ciu-1',
    zonaId: 'zona-9',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1', syncVersion: 4),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = UbicacionLocalDataSourceDrift(
      db,
      encolador: EncoladorSyncEnMemoria(),
      marcarDuplicado: EncoladorMarcarDuplicadoFalso(),
      estadoDeLasCasas: HouseStatusUpdaterEspia(),
    );
  });
  tearDown(() => db.close());

  Future<void> trabajo(String id, String estado, {String codigo = ''}) => db
      .into(db.syncQueue)
      .insertOnConflictUpdate(
        SyncQueueCompanion.insert(
          id: id,
          clientOpId: 'op-$id',
          entity: 'ubicacion',
          op: 'marcar_como_duplicado',
          payload: '{}',
          rowPk: const Value('ub-b'),
          createdAt: tUnion,
          state: estado,
          code: Value(codigo),
        ),
      );

  Future<UbicacionFila> fila(String id) =>
      (db.select(db.ubicaciones)..where((u) => u.id.equals(id))).getSingle();
  Future<EspacioFila> espacio(String id) =>
      (db.select(db.espacios)..where((e) => e.id.equals(id))).getSingle();
  Future<UnionLocalFila> union(String id) =>
      (db.select(db.unionesLocales)..where((u) => u.trabajoId.equals(id))).getSingle();

  /// A (casa con `esp-a`), B (casa con `esp-b` con su persona, visita y entrevista, y el depto
  /// `esp-b2`), una nota del lugar de B, y C (edificio con `esp-c`).
  Future<void> sembrar() async {
    await local.insertar(ubicacion('ub-a'));
    await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
    await local.insertar(ubicacion('ub-b'));
    await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-b');
    await sembrarEspacio(db, id: 'esp-b2', ubicacionId: 'ub-b', numeroDepto: '2B');
    await sembrarVinculo(db, id: 'ep-b', espacioId: 'esp-b', personaId: 'per-b');
    await insertarVisita(db, visitaDe('vis-b', espacio: 'esp-b', vinculo: 'ep-b'));
    await insertarAgenda(db, agendaDe('ag-b', espacio: 'esp-b', vinculo: 'ep-b'));
    await db
        .into(db.notas)
        .insert(
          NotasCompanion.insert(
            id: 'n-b',
            targetType: TipoObjetivoNota.ubicacion,
            targetId: 'ub-b',
            texto: 'Atiende de tarde',
            createdAt: t0,
            updatedAt: t0,
          ),
        );
    await local.insertar(ubicacion('ub-c', tipo: TipoUbicacion.edificio));
    await sembrarEspacio(db, id: 'esp-c', ubicacionId: 'ub-c', numeroDepto: '1A');
  }

  /// Cuántas filas hay en cada tabla del colportor, con las dadas de baja: deshacer no borra.
  Future<List<int>> conteos() async {
    Future<int> cuenta(String tabla) async =>
        (await db.customSelect('SELECT COUNT(*) AS n FROM $tabla').getSingle()).read<int>('n');
    return [
      for (final t in ['ubicacion', 'espacio', 'espacio_persona', 'visita', 'agenda', 'nota'])
        await cuenta(t),
    ];
  }

  test('dado B a A y después A a C, cuando solo la primera vuelve rechazada, B vuelve sin perder '
      'nada: lo que ya subió a C queda donde está y no se borra ninguna fila', () async {
    await sembrar();
    await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
    await local.unirDuplicada('ub-c', 'ub-a', ahora: tUnion2);
    final antes = await conteos();
    await trabajo('trabajo-1', EstadoJob.invalid, codigo: 'UB003');
    await trabajo('trabajo-2', EstadoJob.pending);

    final hechas = await local.deshacerUnionesRechazadas(ahora: tDeshacer);

    expect(hechas.map((h) => (h.conservadaId, h.duplicadaId)), [('ub-a', 'ub-b')]);
    expect(await conteos(), antes, reason: 'ninguna fila se borra');
    expect((await fila('ub-b')).deletedAt, isNull, reason: 'B vuelve');
    expect((await fila('ub-a')).deletedAt, isNotNull, reason: 'A sigue unida a C');
    expect((await union('trabajo-1')).estado, EstadoUnionLocal.deshecha);
    expect((await union('trabajo-2')).estado, EstadoUnionLocal.aplicada);
    // Todo lo de B sigue vivo en algún lado: nada quedó huérfano ni de baja por error.
    expect((await espacio('esp-b2')).deletedAt, isNull);
    expect((await espacio('esp-b')).deletedAt, isNull);
  });

  test('dado B a A y después A a C, cuando solo la segunda vuelve rechazada, A vuelve y lo de B '
      'sigue en A porque esa unión no se rechazó', () async {
    await sembrar();
    await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
    await local.unirDuplicada('ub-c', 'ub-a', ahora: tUnion2);
    final antes = await conteos();
    await trabajo('trabajo-1', EstadoJob.pending);
    await trabajo('trabajo-2', EstadoJob.invalid, codigo: '42501');

    final hechas = await local.deshacerUnionesRechazadas(ahora: tDeshacer);

    expect(hechas.map((h) => (h.conservadaId, h.duplicadaId, h.sinVolver)), [('ub-c', 'ub-a', 0)]);
    expect(await conteos(), antes);
    expect((await fila('ub-a')).deletedAt, isNull, reason: 'A vuelve');
    expect((await fila('ub-b')).deletedAt, isNotNull, reason: 'B sigue unida a A');
    expect((await espacio('esp-b2')).ubicacionId, 'ub-a');
    expect((await union('trabajo-1')).estado, EstadoUnionLocal.aplicada);
  });

  test('dado un rechazo, deshacer dos veces seguidas no cambia nada la segunda vez', () async {
    await sembrar();
    await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
    await trabajo('trabajo-1', EstadoJob.invalid, codigo: 'CG001');
    await local.deshacerUnionesRechazadas(ahora: tDeshacer);
    final antes = await conteos();
    final fb = await fila('ub-b');

    final otra = await local.deshacerUnionesRechazadas(
      ahora: tDeshacer.add(const Duration(hours: 1)),
    );

    expect(otra, isEmpty);
    expect(await conteos(), antes);
    expect((await fila('ub-b')).updatedAt, fb.updatedAt);
  });
}

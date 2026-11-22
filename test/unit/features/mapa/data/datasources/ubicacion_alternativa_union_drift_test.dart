// La ubicación alternativa de cobranza (HU-UBI-013) cuando sus ubicaciones se unen como duplicadas
// (HU-UBI-006) contra las tablas reales: la alternativa que era B pasa a ser A, y nadie se queda con
// una alternativa «dada de baja» que en realidad es la que se conservó. El reapuntado es el de la
// unión (`_reapuntarAlternativas`): no encola nada por fila, lo aplica el servidor al correr el trabajo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/duplicados_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 13, 45, 10, 123);
  final union = DateTime.utc(2026, 10, 26, 9, 30);

  Auditoria auditoria() => Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1');

  UbicacionModel ubicacion(String id) => UbicacionModel(
    id: id,
    tipo: TipoUbicacion.edificio,
    calle: 'Av. Italia',
    numero: '1234',
    lat: -34.891,
    lon: -56.125,
    ciudadId: 'mvd',
    auditoria: auditoria(),
  );

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late EncoladorMarcarDuplicadoFalso marcador;
  late UbicacionLocalDataSourceDrift local;

  /// Un vínculo directo en la tabla: [alternativa] es lo que se prueba.
  Future<void> vincular(String personaId, String espacioId, {String? alternativa}) => db
      .into(db.espacioPersonas)
      .insert(
        EspacioPersonasCompanion.insert(
          id: 'ep-$personaId',
          espacioId: espacioId,
          personaId: personaId,
          ubicacionCobranzaAltId: Value(alternativa),
          createdAt: t0,
          updatedAt: t0,
          createdBy: const Value('col-1'),
        ),
      );

  Future<String?> alternativaDe(String personaId) async => (await (db.select(
    db.espacioPersonas,
  )..where((v) => v.personaId.equals(personaId))).getSingle()).ubicacionCobranzaAltId;

  Future<void> unir() => local.unirDuplicada('ub-a', 'ub-b', ahora: union);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    marcador = EncoladorMarcarDuplicadoFalso();
    local = UbicacionLocalDataSourceDrift(db, encolador: encolador, marcarDuplicado: marcador);
    // A y B son el mismo edificio cargado dos veces; C es otro lugar, donde vive alguien que cobra en B.
    for (final (id, espacio) in [('ub-a', 'a1'), ('ub-b', 'b1'), ('ub-c', 'c1')]) {
      await local.insertar(ubicacion(id));
      await local.insertarEspacio(
        EspacioModel(id: espacio, ubicacionId: id, numeroDepto: '1', auditoria: auditoria()),
      );
    }
    encolador.encolados.clear();
  });

  tearDown(() => db.close());

  test('dada una persona de otro lugar que cobra en B, cuando B se une a A, ahora cobra en A y no '
      'se encola nada de eso: lo aplica el servidor al correr la unión', () async {
    await vincular('per-1', 'c1', alternativa: 'ub-b');

    await unir();

    expect(await alternativaDe('per-1'), 'ub-a');
    expect(encolador.encolados.where((c) => c.entidad == 'espacio_persona'), isEmpty);
    expect(marcador.encolados, hasLength(1));
  });

  test(
    'dada una persona que vive en A y cobraba en B, cuando se unen, la alternativa pasa a ser A y no '
    'se encola nada: la unión no quita la alternativa que queda siendo su propia ubicación '
    '(pendiente de decisión, ver el PR)',
    () async {
      await vincular('per-1', 'a1', alternativa: 'ub-b');

      await unir();

      expect(await alternativaDe('per-1'), 'ub-a');
      expect(encolador.encolados.where((c) => c.entidad == 'espacio_persona'), isEmpty);
    },
  );

  test('dada una persona que vive en B y cobraba en A, cuando se unen, su depto pasa a A y la '
      'alternativa sigue siendo A, sin tocar ni encolar nada', () async {
    await vincular('per-1', 'b1', alternativa: 'ub-a');

    await unir();

    expect(await alternativaDe('per-1'), 'ub-a');
    expect(encolador.encolados.where((c) => c.entidad == 'espacio_persona'), isEmpty);
  });

  test(
    'dadas otras alternativas y personas sin alternativa, cuando se unen A y B, ninguna se toca',
    () async {
      await vincular('per-1', 'c1', alternativa: 'ub-c');
      await vincular('per-2', 'a1');

      await unir();

      expect(await alternativaDe('per-1'), 'ub-c');
      expect(await alternativaDe('per-2'), isNull);
      final fila = await (db.select(
        db.espacioPersonas,
      )..where((v) => v.personaId.equals('per-1'))).getSingle();
      expect(fila.updatedAt, t0);
    },
  );

  test('dada la unión ya hecha, cuando se repite, no cambia nada más', () async {
    await vincular('per-1', 'c1', alternativa: 'ub-b');
    await vincular('per-2', 'a1', alternativa: 'ub-b');
    await unir();
    encolador.encolados.clear();

    await unir();

    expect(await alternativaDe('per-1'), 'ub-a');
    expect(await alternativaDe('per-2'), 'ub-a');
    expect(encolador.encolados, isEmpty);
  });

  test(
    'dado que el motor rechaza el trabajo de la unión, cuando se une, la transacción se revierte entera: la '
    'alternativa sigue siendo B y B sigue viva',
    () async {
      await vincular('per-1', 'a1', alternativa: 'ub-b');
      await vincular('per-2', 'c1', alternativa: 'ub-b');
      marcador.fallarCon = StateError('sin cola');

      await expectLater(unir(), throwsStateError);

      expect(await alternativaDe('per-1'), 'ub-b');
      expect(await alternativaDe('per-2'), 'ub-b');
      expect((await local.obtener('ub-b'))!.auditoria.estaBorrada, isFalse);
    },
  );
}

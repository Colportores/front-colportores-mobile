// Dónde cuelga hoy la visita de una entrevista que empezó antes («Sin salida», 25/10; #450), contra
// las tablas reales en memoria: la unión de duplicados, la baja de la persona y la casa que ya no
// está.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/destino_de_entrevista_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/services/destino_de_entrevista.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DestinoDeEntrevistaDrift destino;

  Future<void> sembrarPersona({String id = 'per-1', DateTime? borrada}) => db
      .into(db.personas)
      .insert(
        PersonasCompanion.insert(
          id: id,
          nombre: 'Pedro',
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrada),
        ),
      );

  Future<DestinoDeEntrevista?> resolver({
    String espacioId = 'esp-1',
    String espacioPersonaId = 'ep-1',
  }) => destino.resolver(espacioId: espacioId, espacioPersonaId: espacioPersonaId);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    destino = DestinoDeEntrevistaDrift(db);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  test('todo sigue como al empezar: la misma casa y la misma persona', () async {
    await sembrarPersona();

    expect(
      await resolver(),
      const DestinoDeEntrevista(espacioId: 'esp-1', espacioPersonaId: 'ep-1'),
    );
  });

  test('la unión de duplicados movió el vínculo a la casa que quedó: la visita va ahí', () async {
    await sembrarPersona();
    await sembrarEspacio(db, id: 'esp-que-quedo', ubicacionId: 'ub-1');
    // El espacio de la entrevista se fundió: de baja, y sus vínculos pasaron al que quedó.
    await (db.update(
      db.espacios,
    )..where((e) => e.id.equals('esp-1'))).write(EspaciosCompanion(deletedAt: Value(t0)));
    await (db.update(db.espacioPersonas)..where((v) => v.id.equals('ep-1'))).write(
      const EspacioPersonasCompanion(espacioId: Value('esp-que-quedo')),
    );

    expect(
      await resolver(),
      const DestinoDeEntrevista(espacioId: 'esp-que-quedo', espacioPersonaId: 'ep-1'),
    );
  });

  test('la persona dada de baja: la visita queda de la casa, sin persona', () async {
    await sembrarPersona(borrada: t0);

    expect(await resolver(), const DestinoDeEntrevista(espacioId: 'esp-1'));
  });

  test('el vínculo dado de baja: sin persona, en la casa del vínculo', () async {
    await sembrarPersona();
    await (db.update(
      db.espacioPersonas,
    )..where((v) => v.id.equals('ep-1'))).write(EspacioPersonasCompanion(deletedAt: Value(t0)));

    expect(await resolver(), const DestinoDeEntrevista(espacioId: 'esp-1'));
  });

  test('el vínculo sin su persona (recuperación sin copia): sin persona', () async {
    // sembrarCasa no siembra a `per-1`.
    expect(await resolver(), const DestinoDeEntrevista(espacioId: 'esp-1'));
  });

  test('el vínculo ya no existe: la visita queda de la casa donde empezó, sin persona', () async {
    await (db.delete(db.espacioPersonas)..where((v) => v.id.equals('ep-1'))).go();

    expect(await resolver(), const DestinoDeEntrevista(espacioId: 'esp-1'));
  });

  test('la casa de baja y sin otro lugar: no hay dónde guardarla (null)', () async {
    await sembrarPersona();
    await (db.update(
      db.espacios,
    )..where((e) => e.id.equals('esp-1'))).write(EspaciosCompanion(deletedAt: Value(t0)));

    expect(await resolver(), isNull);
  });

  test('ni el vínculo ni el espacio existen (null)', () async {
    await (db.delete(db.espacioPersonas)..where((v) => v.id.equals('ep-1'))).go();
    await (db.delete(db.espacios)..where((e) => e.id.equals('esp-1'))).go();

    expect(await resolver(), isNull);
  });

  test('un depto de un edificio resuelve su propio depto, no el de al lado', () async {
    await db.close();
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    destino = DestinoDeEntrevistaDrift(db);
    await sembrarEdificio(db);
    await sembrarPersona(id: 'per-2');

    expect(
      await resolver(espacioId: 'esp-2', espacioPersonaId: 'ep-2'),
      const DestinoDeEntrevista(espacioId: 'esp-2', espacioPersonaId: 'ep-2'),
    );
  });
}

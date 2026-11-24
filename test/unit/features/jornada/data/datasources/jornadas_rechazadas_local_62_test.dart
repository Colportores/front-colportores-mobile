// Las jornadas que el servidor no aceptó por empezar antes del inicio de la campaña, y sus visitas
// (HU-AUTH-008, #62; decisión de Cristian del 27/10 sobre backend-supabase#184): leídas de la cola de
// sync, sin cambiarla.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/sync_queue_table.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornadas_rechazadas_data_source.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada_rechazada.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

const _usuario = 'col-1';
final _inicio = DateTime.utc(2026, 11, 20, 12);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late JornadasRechazadasLocal fuente;
  var n = 0;

  setUp(() {
    n = 0;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    fuente = JornadasRechazadasLocal(db);
  });
  tearDown(() => db.close());

  Future<void> jornada(
    String id, {
    String colportor = _usuario,
    DateTime? inicio,
    bool deBaja = false,
  }) => db
      .into(db.jornadas)
      .insert(
        JornadasCompanion.insert(
          id: id,
          colportorId: colportor,
          inicio: inicio ?? _inicio,
          createdAt: inicio ?? _inicio,
          updatedAt: inicio ?? _inicio,
          deletedAt: Value(deBaja ? _inicio : null),
        ),
      );

  Future<void> visita(String id, {String? jornadaId}) => db
      .into(db.visitas)
      .insert(
        VisitasCompanion.insert(
          id: id,
          espacioId: 'esp-1',
          fecha: _inicio,
          tipoResultado: 'NO_CONTESTO',
          colportorId: _usuario,
          jornadaId: Value(jornadaId),
          createdAt: _inicio,
          updatedAt: _inicio,
        ),
      );

  Future<void> encolar(
    String entidad,
    String pk, {
    required String estado,
    String codigo = '',
    String op = 'insert',
  }) => db
      .into(db.syncQueue)
      .insert(
        SyncQueueCompanion.insert(
          id: 'job-${++n}',
          clientOpId: 'op-$n',
          entity: entidad,
          op: op,
          payload: '{}',
          createdAt: DateTime.utc(2026, 11, 20, 12, 0, n),
          state: estado,
          code: Value(codigo),
          rowPk: Value(pk),
        ),
      );

  Future<List<List<JornadaRechazada>>> escuchar({String colportor = _usuario}) async {
    final emisiones = <List<JornadaRechazada>>[];
    final suscripcion = fuente.observar(colportor).listen(emisiones.add);
    addTearDown(suscripcion.cancel);
    await pumpEventQueue(times: 100);
    return emisiones;
  }

  test('sin nada rechazado emite la lista vacía', () async {
    await jornada('j-1');
    await encolar('jornada', 'j-1', estado: EstadoJob.pending);

    expect(await escuchar(), [isEmpty]);
  });

  test('la jornada cuyo alta volvió invalid con 42501, con 0 visitas', () async {
    await jornada('j-1');
    await encolar('jornada', 'j-1', estado: EstadoJob.invalid, codigo: '42501');

    expect(await escuchar(), [
      [JornadaRechazada(id: 'j-1', inicio: _inicio, visitas: 0)],
    ]);
  });

  test('cuenta las visitas de esa jornada que volvieron con 23503, cada una una vez', () async {
    await jornada('j-1');
    await encolar('jornada', 'j-1', estado: EstadoJob.invalid, codigo: '42501');
    for (final id in ['v-1', 'v-2', 'v-3']) {
      await visita(id, jornadaId: 'j-1');
      await encolar('visita', id, estado: EstadoJob.invalid, codigo: '23503');
    }
    // Una visita de la jornada que sigue en la cola, otra con otro rechazo y otra de otra jornada.
    await visita('v-4', jornadaId: 'j-1');
    await encolar('visita', 'v-4', estado: EstadoJob.pending);
    await visita('v-5', jornadaId: 'j-1');
    await encolar('visita', 'v-5', estado: EstadoJob.invalid, codigo: '23514');
    await visita('v-6');
    await encolar('visita', 'v-6', estado: EstadoJob.invalid, codigo: '23503');

    expect((await escuchar()).single.single.visitas, 3);
  });

  test('dos jornadas rechazadas: cada una con sus visitas, la más nueva primero', () async {
    final antes = DateTime.utc(2026, 11, 18, 12);
    await jornada('j-1', inicio: antes);
    await jornada('j-2');
    await encolar('jornada', 'j-1', estado: EstadoJob.invalid, codigo: '42501');
    await encolar('jornada', 'j-2', estado: EstadoJob.invalid, codigo: '42501');
    await visita('v-1', jornadaId: 'j-1');
    await encolar('visita', 'v-1', estado: EstadoJob.invalid, codigo: '23503');

    expect((await escuchar()).single, [
      JornadaRechazada(id: 'j-2', inicio: _inicio, visitas: 0),
      JornadaRechazada(id: 'j-1', inicio: antes, visitas: 1),
    ]);
  });

  test('otro rechazo de la jornada (no 42501) o un update rechazado no es esta causa', () async {
    await jornada('j-1');
    await encolar('jornada', 'j-1', estado: EstadoJob.invalid, codigo: '23514');
    await jornada('j-2');
    await encolar('jornada', 'j-2', estado: EstadoJob.invalid, codigo: '42501', op: 'update');

    expect(await escuchar(), [isEmpty]);
  });

  test('solo las jornadas de ese colportor y sin baja', () async {
    await jornada('j-1', colportor: 'otro');
    await encolar('jornada', 'j-1', estado: EstadoJob.invalid, codigo: '42501');
    await jornada('j-2', deBaja: true);
    await encolar('jornada', 'j-2', estado: EstadoJob.invalid, codigo: '42501');

    expect(await escuchar(), [isEmpty]);
  });

  test('reactivo: cuando el servidor rechaza el alta, o una visita más, vuelve a emitir', () async {
    await jornada('j-1');
    await encolar('jornada', 'j-1', estado: EstadoJob.inFlight);
    final emisiones = await escuchar();
    expect(emisiones.last, isEmpty);

    await (db.update(db.syncQueue)..where((q) => q.rowPk.equals('j-1'))).write(
      const SyncQueueCompanion(state: Value(EstadoJob.invalid), code: Value('42501')),
    );
    await pumpEventQueue(times: 100);
    expect(emisiones.last.single.visitas, 0);

    await visita('v-1', jornadaId: 'j-1');
    await encolar('visita', 'v-1', estado: EstadoJob.invalid, codigo: '23503');
    await pumpEventQueue(times: 100);
    expect(emisiones.last.single.visitas, 1);
  });

  test('sin la base abierta (no hay sesión) emite la lista vacía', () async {
    expect(await JornadasRechazadasLocal(null).observar(_usuario).first, isEmpty);
  });
}
